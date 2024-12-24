//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DevOpsTools} from "../lib/foundry-devops/src/DevOpsTools.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    NetworkConfig config;
    address mostRencentDeployedDSC;

    address collaternal_WETH_Sepolia = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address collaternal_WBTC_Sepolia = 0x71A800f732A0AA2dAA35E0C44229243CB4368565;
    address wethUsdPriceFeed_Sepolia = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address wbtcUsdPriceFeed_Sepolia = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;

    uint8 WETH_USD_DECIMALS = 8;
    int256 WETH_USD_INITIAL_PRICE = 2000e8;
    int256 WBTC_USD_INITIAL_PRICE = 10000e8;

    bool anvilConfigInitialized = false;

    struct NetworkConfig {
        address dscAddr;
        address[] collateralAddresses;
        address[] priceFeedAddresses;
    }

    constructor() {
        mostRencentDeployedDSC = DevOpsTools.get_most_recent_deployment("DecentralizedStableCoin", block.chainid);
    }

    function getConfig() external returns (NetworkConfig memory) {
        if (block.chainid == 11155111) {
            return _getSepoliaEthConfig();
        } else {
            return _getOrCreateAnvilConfig();
        }
    }

    function _getSepoliaEthConfig() internal returns (NetworkConfig memory) {
        address[] memory collateralAddresses = new address[](2);
        collateralAddresses[0] = collaternal_WETH_Sepolia;
        collateralAddresses[1] = collaternal_WBTC_Sepolia;
        address[] memory priceFeedAddresses = new address[](2);
        priceFeedAddresses[0] = wethUsdPriceFeed_Sepolia;
        priceFeedAddresses[1] = wbtcUsdPriceFeed_Sepolia;
        config = NetworkConfig({
            dscAddr: mostRencentDeployedDSC,
            collateralAddresses: collateralAddresses,
            priceFeedAddresses: priceFeedAddresses
        });
        return config;
    }

    function _getOrCreateAnvilConfig() internal returns (NetworkConfig memory) {
        if (anvilConfigInitialized) {
            return config;
        }
        anvilConfigInitialized = true;
        vm.startBroadcast();
        MockV3Aggregator wethUsdPriceFeedMock = new MockV3Aggregator(WETH_USD_DECIMALS, WETH_USD_INITIAL_PRICE);
        MockV3Aggregator wbtcUsdPriceFeedMock = new MockV3Aggregator(WETH_USD_DECIMALS, WBTC_USD_INITIAL_PRICE);
        ERC20Mock wethMock = new ERC20Mock();
        ERC20Mock wbtcMock = new ERC20Mock();
        vm.stopBroadcast();
        address[] memory collateralAddresses = new address[](2);
        collateralAddresses[0] = address(wethMock);
        collateralAddresses[1] = address(wbtcMock);
        address[] memory priceFeedAddresses = new address[](2);
        priceFeedAddresses[0] = address(wethUsdPriceFeedMock);
        priceFeedAddresses[1] = address(wbtcUsdPriceFeedMock);
        config = NetworkConfig({
            dscAddr: mostRencentDeployedDSC,
            collateralAddresses: collateralAddresses,
            priceFeedAddresses: priceFeedAddresses
        });
        return config;
    }
}
