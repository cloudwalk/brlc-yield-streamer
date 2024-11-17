// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { YieldStreamerV2 } from "./YieldStreamerV2.sol";

/**
 * @title YieldStreamerV2Testable contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Implements additional functions to test private and internal functions of base contracts.
 */
contract YieldStreamerV2Testable is YieldStreamerV2 {
    // ------------------ Yield Math ------------------------------- //

    function getAccruePreview(
        YieldState memory state,
        YieldRate[] memory rates,
        uint256 currentTimestamp
    ) external pure returns (AccruePreview memory) {
        return _getAccruePreview(state, rates, currentTimestamp);
    }

    function calculateYield(
        CalculateYieldParams memory params,
        YieldRate[] memory rates
    ) external pure returns (YieldResult[] memory) {
        return _calculateYield(params, rates);
    }

    function compoundYield(CompoundYieldParams memory params) external pure returns (YieldResult memory) {
        return _compoundYield(params);
    }

    function calculateTieredYield(
        uint256 amount,
        uint256 elapsedSeconds,
        RateTier[] memory rateTiers
    ) external pure returns (uint256, uint256[] memory) {
        return _calculateTieredYield(amount, elapsedSeconds, rateTiers);
    }

    function calculateSimpleYield(
        uint256 amount,
        uint256 rate,
        uint256 elapsedSeconds
    ) external pure returns (uint256) {
        return _calculateSimpleYield(amount, rate, elapsedSeconds);
    }


    function inRangeYieldRates(
        YieldRate[] memory rates,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) external pure returns (uint256, uint256) {
        return _inRangeYieldRates(rates, fromTimestamp, toTimestamp);
    }

    function aggregateYield(YieldResult[] memory yieldResults) external pure returns (uint256, uint256) {
        return _aggregateYield(yieldResults);
    }

    // ------------------ Timestamp ------------------------------- //

    function effectiveTimestamp(uint256 timestamp) external pure returns (uint256) {
        return _effectiveTimestamp(timestamp);
    }

    // ------------------ Utility --------------------------------- //

    function truncateArray(
        uint256 startIndex,
        uint256 endIndex,
        YieldRate[] memory yieldRates
    ) external pure returns (YieldRate[] memory) {
        return _truncateArray(startIndex, endIndex, yieldRates);
    }

    function calculateFee(uint256 amount) external pure returns (uint256) {
        return _calculateFee(amount);
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
