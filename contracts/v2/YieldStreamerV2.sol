// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { YieldStreamerStorage } from "./YieldStreamerStorage.sol";
import { YieldStreamerPrimary } from "./YieldStreamerPrimary.sol";
import { YieldStreamerConfiguration } from "./YieldStreamerConfiguration.sol";

contract YieldStreamerV2 is YieldStreamerStorage, YieldStreamerPrimary, YieldStreamerConfiguration {
    constructor(address _underlyingToken) {
        underlyingToken = _underlyingToken;
    }
}
