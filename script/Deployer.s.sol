//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {Script} from "forge-std/Script.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {DevOpsTools} from "../lib/foundry-devops/src/DevOpsTools.sol";

contract Deployer is Script {
    DSCEngine dscEngine;
    DecentralizedStableCoin decentralizedStableCoin;
    HelperConfig.NetworkConfig config;

    function run() external returns (DSCEngine, DecentralizedStableCoin, HelperConfig.NetworkConfig memory) {
        HelperConfig helperConfig = new HelperConfig();
        decentralizedStableCoin = _deployDecentralizedStableCoin();

        config = helperConfig.getConfig();
        config.dscAddr = address(decentralizedStableCoin);
        dscEngine = _deployDSCEngine();
        return (dscEngine, decentralizedStableCoin, config);
    }

    function _deployDecentralizedStableCoin() internal returns (DecentralizedStableCoin _decentralizedStableCoin) {
        vm.startBroadcast();
        _decentralizedStableCoin = new DecentralizedStableCoin();
        vm.stopBroadcast();
    }

    function _deployDSCEngine() internal returns (DSCEngine _dscEngine) {
        vm.startBroadcast();
        _dscEngine = new DSCEngine(config.dscAddr, config.collateralAddresses, config.priceFeedAddresses);
        decentralizedStableCoin.transferOwnership(address(_dscEngine));
        vm.stopBroadcast();
    }
}
