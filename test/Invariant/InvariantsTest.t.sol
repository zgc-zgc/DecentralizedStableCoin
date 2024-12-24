//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console2} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {Handler} from "./Handler.t.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Deployer} from "../../script/Deployer.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InvariantsTest is StdInvariant, Test {
    DSCEngine public dsce;
    DecentralizedStableCoin public dsc;
    HelperConfig.NetworkConfig public config;
    Handler public handler;

    function setUp() public {
        Deployer deployer = new Deployer();
        (dsce, dsc, config) = deployer.run();
        handler = new Handler(dsc, dsce, config);
        targetContract(address(handler));
    }

    function invariant_DSCTotalSupplyMustBeLessThanTotalCollateral() public view {
        uint256 dscTotalSupply = dsc.totalSupply();
        uint256 totalCollateralValue;

        for (uint256 i = 0; i < config.collateralAddresses.length; i++) {
            address token = config.collateralAddresses[i];
            uint256 amount = IERC20(token).balanceOf(address(dsce));
            uint256 price = dsce.getUsdValue(token, amount);
            totalCollateralValue += price;
        }
        console2.log("dscTotalSupply", dscTotalSupply);
        console2.log("totalCollateralValue", totalCollateralValue);
        console2.log("timeMinted", handler.timeMinted());
        console2.log("timeRedeemed", handler.timeRedeemed());
        console2.log("timeDeposited", handler.timeDeposited());
        assert(dscTotalSupply <= totalCollateralValue);
    }
}
