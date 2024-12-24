//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {Test, console2} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {Deployer} from "../../script/Deployer.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract DSCTest is Test {
    DecentralizedStableCoin public decentralizedStableCoin;
    DSCEngine public dscEngine;
    HelperConfig.NetworkConfig public config;

    address WETH;
    address WBTC;
    address WETH_USD_PRICE_FEED;
    address WBTC_USD_PRICE_FEED;

    address USER = makeAddr("USER");
    address LIQUIDATOR = makeAddr("LIQUIDATOR");

    uint256 AMOUNT_COLLATERAL = 10 ether;
    uint256 STARTING_ERC20_BALANCE = 10 ether;

    uint256 AMOUNT_WETH_TO_REDEEM = 1e18;

    uint256 AMOUNT_DSC_TO_MINT_BEYOND_HEALTH_FACTOR_WITH_WETH = 2e22;
    uint256 AMOUNT_DSC_TO_MINT_BELOW_HEALTH_FACTOR_WITH_WETH = 1e22;
    uint256 AMOUNT_DSC_TO_MINT_BEYOND_HEALTH_FACTOR_WITH_WBTC = 1e23;
    uint256 AMOUNT_DSC_TO_MINT_BELOW_HEALTH_FACTOR_WITH_WBTC = 5e22;

    uint256 AMOUNT_DSC_TO_BURN = 1e20;

    uint256 BOUNS_SHARE = 10;
    uint256 BOUNS_PRECISION = 100;

    int256 LOWER_ETH_PRICE = 1900e8;

    function setUp() public {
        Deployer deployer = new Deployer();
        (dscEngine, decentralizedStableCoin, config) = deployer.run();
        (WETH, WBTC) = (config.collateralAddresses[0], config.collateralAddresses[1]);
        (WETH_USD_PRICE_FEED, WBTC_USD_PRICE_FEED) = (config.priceFeedAddresses[0], config.priceFeedAddresses[1]);
        ERC20Mock(WETH).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(WBTC).mint(USER, STARTING_ERC20_BALANCE);
    }

    function test_getUsdValue_success() public view {
        uint256 ethAmount = 2e18;
        uint256 expectedValue = 4000e18;
        uint256 actualValue = dscEngine.getUsdValue(WETH, ethAmount);
        assertEq(actualValue, expectedValue);
    }

    function test_depositCollateral_revert_whenAmountIsZero() external {
        vm.startPrank(USER);
        ERC20Mock(WETH).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__MustMoreThanZero.selector);
        dscEngine.depositCollateral(WETH, 0);
        vm.stopPrank();
    }

    function test_depositCollateral_revert_whenCollaternalNotAllowed() external {
        vm.startBroadcast();
        ERC20Mock wbnb = new ERC20Mock();
        wbnb.mint(USER, STARTING_ERC20_BALANCE);
        vm.stopBroadcast();
        vm.startPrank(USER);
        wbnb.approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NotAllowedCollateral.selector, address(wbnb)));
        dscEngine.depositCollateral(address(wbnb), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_depositCollateral_revert_whenNotApproved() external {
        vm.startPrank(USER);
        vm.expectRevert();
        dscEngine.depositCollateral(WETH, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function test_depositCollateral_success() external {
        vm.startPrank(USER);
        ERC20Mock(WETH).approve(address(dscEngine), AMOUNT_COLLATERAL);
        vm.recordLogs();
        dscEngine.depositCollateral(WETH, AMOUNT_COLLATERAL);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        vm.stopPrank();
        assertEq(ERC20Mock(WETH).balanceOf(address(dscEngine)), AMOUNT_COLLATERAL);
        assertEq(dscEngine.getUserBalance(USER, WETH), AMOUNT_COLLATERAL);
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("CollateralDeposited(address,address,uint256)")) {
                address actualUser = address(uint160(uint256(entries[i].topics[1])));
                address actualCollaternal = address(uint160(uint256(entries[i].topics[2])));
                uint256 actualAmount = uint256(entries[i].topics[3]);
                assertEq(actualUser, USER);
                assertEq(actualCollaternal, WETH);
                assertEq(actualAmount, AMOUNT_COLLATERAL);
                break;
            }
        }
    }

    modifier wethDespoited() {
        vm.startPrank(USER);
        ERC20Mock(WETH).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(WETH, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier wbtcDespoited() {
        vm.startPrank(USER);
        ERC20Mock(WBTC).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(WBTC, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function test_constructor_revert_whenCollateralAndPriceFeedLengthMismatch() external {
        address[] memory collateralAddresses = new address[](2);
        collateralAddresses[0] = WETH;
        collateralAddresses[1] = WBTC;
        address[] memory priceFeedAddresses = new address[](1);
        priceFeedAddresses[0] = WETH_USD_PRICE_FEED;
        vm.expectRevert(DSCEngine.DSCEngine__CollateralAndPriceFeedLengthMismatch.selector);
        new DSCEngine(address(decentralizedStableCoin), collateralAddresses, priceFeedAddresses);
    }

    function test_constructor_success() external view {
        assertEq(address(dscEngine.i_dsc()), address(decentralizedStableCoin));
        assertEq(dscEngine.getCollateralAddresses().length, config.collateralAddresses.length);
        assertEq(dscEngine.getCollateralAddresses()[0], WETH);
        assertEq(dscEngine.getCollateralAddresses()[1], WBTC);
        for (uint256 i = 0; i < config.priceFeedAddresses.length; i++) {
            assertEq(dscEngine.getPriceFeedAddresses(i), config.priceFeedAddresses[i]);
        }
    }

    function test_mintDSC_revert_whenHealthFactorIsBroken() external wethDespoited {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        dscEngine.mintDSC(AMOUNT_DSC_TO_MINT_BEYOND_HEALTH_FACTOR_WITH_WETH);
        vm.stopPrank();
    }

    function test_mintDSC_success() external wethDespoited {
        vm.startPrank(USER);
        dscEngine.mintDSC(AMOUNT_DSC_TO_MINT_BELOW_HEALTH_FACTOR_WITH_WETH);
        vm.stopPrank();
        assertEq(decentralizedStableCoin.balanceOf(USER), AMOUNT_DSC_TO_MINT_BELOW_HEALTH_FACTOR_WITH_WETH);
        assertEq(dscEngine.getUserToMinted(USER), AMOUNT_DSC_TO_MINT_BELOW_HEALTH_FACTOR_WITH_WETH);
    }

    function test_redeemCollateral_revert_whenHealthFactorIsBroken() external wethDespoited {
        vm.startPrank(USER);
        dscEngine.mintDSC(AMOUNT_DSC_TO_MINT_BELOW_HEALTH_FACTOR_WITH_WETH);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        dscEngine.redeemCollateral(1, WETH);
        vm.stopPrank();
    }

    function test_redeemCollateral_success() external wethDespoited {
        uint256 startingBalance = ERC20Mock(WETH).balanceOf(USER);
        uint256 startingCollateralDespoited = dscEngine.getUserBalance(USER, WETH);
        vm.startPrank(USER);
        vm.recordLogs();
        dscEngine.redeemCollateral(AMOUNT_WETH_TO_REDEEM, WETH);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        vm.stopPrank();
        assertEq(ERC20Mock(WETH).balanceOf(USER), startingBalance + AMOUNT_WETH_TO_REDEEM);
        assertEq(dscEngine.getUserBalance(USER, WETH), startingCollateralDespoited - AMOUNT_WETH_TO_REDEEM);
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("LiquidationRedeemed(address, address, address, uint256)")) {
                assertEq(address(uint160(uint256(entries[i].topics[1]))), USER);
                assertEq(address(uint160(uint256(entries[i].topics[2]))), USER);
                assertEq(address(uint160(uint256(entries[i].topics[3]))), WETH);
                assertEq(abi.decode(entries[i].data, (uint256)), AMOUNT_WETH_TO_REDEEM);
                break;
            }
        }
    }

    function test_burnDSC_success() external wethDespoited {
        vm.startPrank(USER);
        dscEngine.mintDSC(AMOUNT_DSC_TO_MINT_BELOW_HEALTH_FACTOR_WITH_WETH);
        uint256 startingDSCMinted = dscEngine.getUserToMinted(USER);
        uint256 startingDSCBalanceOfUser = decentralizedStableCoin.balanceOf(USER);
        uint256 startingDSCBalanceOfEngine = decentralizedStableCoin.balanceOf(address(dscEngine));
        ERC20Mock(address(decentralizedStableCoin)).approve(address(dscEngine), AMOUNT_DSC_TO_BURN);
        dscEngine.burnDSC(AMOUNT_DSC_TO_BURN);
        vm.stopPrank();
        assertEq(decentralizedStableCoin.balanceOf(address(dscEngine)), startingDSCBalanceOfEngine);
        assertEq(decentralizedStableCoin.balanceOf(USER), startingDSCBalanceOfUser - AMOUNT_DSC_TO_BURN);
        assertEq(dscEngine.getUserToMinted(USER), startingDSCMinted - AMOUNT_DSC_TO_BURN);
    }

    function test_liquidate_revert_whenHealthFactorIsOK() external wethDespoited {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOK.selector);
        dscEngine.liquidate(USER, WETH, 1);
        vm.stopPrank();
    }

    function test_liquidate_success() external wethDespoited {
        vm.startPrank(USER);
        dscEngine.mintDSC(AMOUNT_DSC_TO_MINT_BELOW_HEALTH_FACTOR_WITH_WETH);
        vm.stopPrank();
        uint256 userStartingBalanceOfWETHCollateral = dscEngine.getUserBalance(USER, WETH);
        uint256 userStartingDSCMinted = dscEngine.getUserToMinted(USER);
        MockV3Aggregator(WETH_USD_PRICE_FEED).updateAnswer(LOWER_ETH_PRICE);
        ERC20Mock(WBTC).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(WBTC).approve(address(dscEngine), STARTING_ERC20_BALANCE);
        dscEngine.depositCollateralAndMintDSC(
            WBTC, STARTING_ERC20_BALANCE, AMOUNT_DSC_TO_MINT_BELOW_HEALTH_FACTOR_WITH_WBTC
        );
        ERC20Mock(address(decentralizedStableCoin)).approve(
            address(dscEngine), AMOUNT_DSC_TO_MINT_BELOW_HEALTH_FACTOR_WITH_WBTC
        );
        uint256 liquidatorStartingBalanceOfWETHCollateral = ERC20Mock(WETH).balanceOf(LIQUIDATOR);
        uint256 liquidatorStartingBalanceOfDSC = decentralizedStableCoin.balanceOf(LIQUIDATOR);
        uint256 debetToCoverInCollateralValue =
            dscEngine._getdebetToCoverInCollateral(WETH, AMOUNT_DSC_TO_MINT_BELOW_HEALTH_FACTOR_WITH_WETH);
        uint256 bouns = (debetToCoverInCollateralValue * BOUNS_SHARE) / BOUNS_PRECISION;
        uint256 totalToRedeem = debetToCoverInCollateralValue + bouns;
        dscEngine.liquidate(USER, WETH, AMOUNT_DSC_TO_MINT_BELOW_HEALTH_FACTOR_WITH_WETH);
        vm.stopPrank();
        assertEq(dscEngine.getUserBalance(USER, WETH), userStartingBalanceOfWETHCollateral - totalToRedeem);
        assertEq(ERC20Mock(WETH).balanceOf(LIQUIDATOR), liquidatorStartingBalanceOfWETHCollateral + totalToRedeem);
        assertEq(
            dscEngine.getUserToMinted(USER), userStartingDSCMinted - AMOUNT_DSC_TO_MINT_BELOW_HEALTH_FACTOR_WITH_WETH
        );
        assertEq(
            decentralizedStableCoin.balanceOf(LIQUIDATOR),
            liquidatorStartingBalanceOfDSC - AMOUNT_DSC_TO_MINT_BELOW_HEALTH_FACTOR_WITH_WETH
        );
    }
}
