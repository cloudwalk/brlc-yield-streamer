// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

interface IYieldStreamerTypes {
    struct YieldState {
        uint256 timestampAtLastUpdate;
        uint256 balanceAtLastUpdate;
        uint256 accruedYield;
        uint256 streamYield;
    }

    struct YieldRate {
        uint256 effectiveDay;
        uint256 value;
    }
}
