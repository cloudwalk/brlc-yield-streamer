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
}
