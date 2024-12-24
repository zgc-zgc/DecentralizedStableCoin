//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

library OrcaleLib {
    error OrcaleLib__TimedOut();

    uint256 constant TIMEDOUT = 2 hours;

    function checkLatestPrice(AggregatorV3Interface priceFeed) public view returns (int256) {
        (, int256 answer,, uint256 updatedAt,) = priceFeed.latestRoundData();
        uint256 timeSinceLastUpdate = block.timestamp - updatedAt;
        if (timeSinceLastUpdate > TIMEDOUT) revert OrcaleLib__TimedOut();
        return answer;
    }
}
