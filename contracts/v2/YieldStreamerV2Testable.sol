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

    function inRangeYieldRates(
        uint32 groupId,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) external view returns (uint256, uint256) {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        return _inRangeYieldRates($.yieldRates[groupId], fromTimestamp, toTimestamp);
    }

    function aggregateYield(YieldResult[] memory yieldResults) external pure returns (uint256, uint256) {
        return _aggregateYield(yieldResults);
    }

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
        uint32 groupId,
        uint256 startIndex,
        uint256 endIndex
    ) external view returns (YieldRate[] memory) {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        return _truncateArray(startIndex, endIndex, $.yieldRates[groupId]);
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
