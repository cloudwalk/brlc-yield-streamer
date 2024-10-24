// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { YieldStreamerV2 } from "./YieldStreamerV2.sol";

/**
 * @title YieldStreamerV2Testable contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Implements additional functions to test private and internal functions of base contracts.
 */
contract YieldStreamerV2Testable is YieldStreamerV2 {
    // ------------------ Timestamp ------------------------------- //

    function nextDay(uint256 timestamp) external pure returns (uint256) {
        return _nextDay(timestamp);
    }

    function effectiveDay(uint256 timestamp) external pure returns (uint256) {
        return _effectiveDay(timestamp);
    }

    function remainingSeconds(uint256 timestamp) external pure returns (uint256) {
        return _remainingSeconds(timestamp);
    }

    function effectiveTimestamp(uint256 timestamp) external pure returns (uint256) {
        return _effectiveTimestamp(timestamp);
    }

    // ------------------ Utility --------------------------------- //

    function truncateArray(
        uint256 startIndex,
        uint256 endIndex,
        YieldRate[] memory rates
    ) external pure returns (YieldRate[] memory) {
        return _truncateArray_memory(startIndex, endIndex, rates);
    }

    function roundDown(uint256 amount) external pure returns (uint256) {
        return _roundDown(amount);
    }

    function roundUp(uint256 amount) external pure returns (uint256) {
        return _roundUp(amount);
    }

    function map(AccruePreview memory accrue) external pure returns (ClaimPreview memory) {
        return _map(accrue);
    }
}
