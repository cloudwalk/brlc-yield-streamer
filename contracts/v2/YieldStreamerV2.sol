// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { YieldStreamerStorage } from "./YieldStreamerStorage.sol";
import { YieldStreamerPrimary } from "./YieldStreamerPrimary.sol";
import { YieldStreamerConfiguration } from "./YieldStreamerConfiguration.sol";

contract YieldStreamerV2 is YieldStreamerStorage, YieldStreamerPrimary, YieldStreamerConfiguration {
    constructor(address _underlyingToken) {
        _yieldStreamerStorage().underlyingToken = _underlyingToken;
    }

    function _accrueYield(
        address account,
        YieldState storage state,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) internal override(YieldStreamerPrimary, YieldStreamerConfiguration) {
        YieldStreamerPrimary._accrueYield(account, state, fromTimestamp, toTimestamp);
    }

    function _blockTimestamp()
        internal
        view
        override(YieldStreamerPrimary, YieldStreamerConfiguration)
        returns (uint256)
    {
        return YieldStreamerPrimary._blockTimestamp();
    }
}
