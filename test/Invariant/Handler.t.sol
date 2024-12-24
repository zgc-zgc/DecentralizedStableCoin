//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console2} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DecentralizedStableCoin public dsc;
    DSCEngine public dsce;
    HelperConfig.NetworkConfig public config;
    uint256 MAX_AMOUNT = type(uint96).max;
    uint256 constant LIQUIDATION_THRESHOLD = 50; //50%mintRate,200%overcollateralized
    uint256 constant LIQUIDATION_PRECISION = 100;

    uint256 public timeMinted;
    uint256 public timeDeposited;
    uint256 public timeRedeemed;
    address[] public usersHasDesposited;
    MockV3Aggregator public PriceFeed;

    constructor(DecentralizedStableCoin _dsc, DSCEngine _dsce, HelperConfig.NetworkConfig memory _config) {
        dsc = _dsc;
        dsce = _dsce;
        config = _config;
    }

    function depositCollateral(uint256 _collateralSeed, uint256 _amount) public {
        _collateralSeed = _collateralSeed % 2 == 0 ? 0 : 1;
        address collateralAddress = config.collateralAddresses[_collateralSeed];
        _amount = bound(_amount, 1, MAX_AMOUNT);
        ERC20Mock(collateralAddress).mint(msg.sender, _amount);
        vm.startPrank(msg.sender);
        ERC20Mock(collateralAddress).approve(address(dsce), _amount);
        dsce.depositCollateral(collateralAddress, _amount);
        vm.stopPrank;
        usersHasDesposited.push(msg.sender);
        timeDeposited++;
    }

    function mintDsc(uint256 _collateralSeed, uint256 _amount) public {
        _collateralSeed = _collateralSeed % 2 == 0 ? 0 : 1;
        address collateralAddress = config.collateralAddresses[_collateralSeed];
        if (usersHasDesposited.length == 0) {
            return;
        }
        address user = usersHasDesposited[_amount % usersHasDesposited.length];
        uint256 amountCollateral = dsce.getUserBalance(user, collateralAddress);
        uint256 valueCollateral = dsce.getUsdValue(collateralAddress, amountCollateral);
        int256 maxToRedeem = int256((valueCollateral * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION)
            - int256(dsce.getUserToMinted(user));
        if (maxToRedeem <= 0) {
            return;
        }
        _amount = bound(_amount, 1, uint256(maxToRedeem));
        vm.startPrank(user);
        dsce.mintDSC(_amount);
        vm.stopPrank();
        timeMinted++;
    }

    function redeemCollateral(uint256 _collateralSeed, uint256 _amount) public {
        _collateralSeed = _collateralSeed % 2 == 0 ? 0 : 1;
        address collateralAddress = config.collateralAddresses[_collateralSeed];
        if (usersHasDesposited.length == 0) {
            return;
        }
        address user = usersHasDesposited[_amount % usersHasDesposited.length];
        uint256 amountCollateral = dsce.getUserBalance(user, collateralAddress);
        uint256 valueCollateral = dsce.getUsdValue(collateralAddress, amountCollateral);
        int256 maxToRedeem = int256((valueCollateral * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION)
            - int256(dsce.getUserToMinted(user));
        if (maxToRedeem <= 0) {
            return;
        }
        _amount = bound(_amount, 1, uint256(maxToRedeem));
        uint256 amountToRedeem = dsce._getdebetToCoverInCollateral(collateralAddress, _amount);
        if (amountToRedeem <= 0) {
            return;
        }
        vm.startPrank(user);
        dsce.redeemCollateral(amountToRedeem, collateralAddress);
        vm.stopPrank();
        timeRedeemed++;
    }
    //Its gonna to break our system,if the collaternal price goes too low
    // function setPriceFeed(uint256 _collateralSeed, uint96 _price) public {
    //     _collateralSeed = _collateralSeed % 2 == 0 ? 0 : 1;
    //     PriceFeed = MockV3Aggregator(config.priceFeedAddresses[_collateralSeed]);
    //     PriceFeed.updateAnswer(int256(uint256(_price)));
    // }
}
