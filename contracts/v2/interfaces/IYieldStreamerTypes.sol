// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IYieldStreamerTypes {
    struct YieldState {
        uint64 timestampAtLastUpdate;
        uint64 balanceAtLastUpdate;
        uint64 accruedYield;
        uint64 streamYield;
    }

    struct YieldRate {
        uint256 effectiveDay;
        uint256 value;
    }

    struct Group {
        uint32 id;
        // uint224 __reserved; // Reserved for future use until the end of the storage slot.
    }

    struct ClaimPreview {
        uint256 yield;
        uint256 fee;
        uint256 balance;
        uint256 rate;
    }

    struct AccruePreview {
        uint256 fromTimestamp;
        uint256 toTimestamp;
        uint256 balance;
        uint256 accruedYieldBefore;
        uint256 streamYieldBefore;
        uint256 accruedYieldAfter;
        uint256 streamYieldAfter;
        YieldRate[] rates;
        YieldResult[] results;
    }

    struct YieldResult {
        uint256 firstDayYield;
        uint256 fullDaysYield;
        uint256 lastDayYield;
    }
}
