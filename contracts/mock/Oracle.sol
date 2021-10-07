// File: @chainlink/contracts/src/v0.7/interfaces/AggregatorV3Interface.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../AggregatorV3Interface.sol";

// File: contracts/PriceOracle.sol
contract PriceOracle is IAggregatorV3Interface {
    uint8 public override decimals = 8;
    string public override description = "BTC/USD";
    uint256 public override version = 1;

    // getRoundData and latestRoundData should both raise "No data present"
    // if they do not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.
    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, 1, 1, block.timestamp, 1);
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, 6000000000000, 1, block.timestamp, 1);
    }
}
