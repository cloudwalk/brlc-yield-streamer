// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IYieldStreamerTypes } from "./interfaces/IYieldStreamerTypes.sol";


contract YieldStreamerStorage is IYieldStreamerTypes {
    uint240 public constant RATE_FACTOR = 10 ** 9;

    uint256 public constant NEGATIVE_TIME_SHIFT = 0;

    bytes32 private constant _YIELD_STREAMER_PRIMARY_STORAGE_LOCATION =
        0x3ffa2d1fa1d7e119f4100ba678d1140b9dc5cebd13fdaaded481a6cf43d1a800;

    /// @custom:storage-location cloudwalk.yieldstreamer.primary.storage
    struct YieldStreamerStorageLayout {
        address underlyingToken;
        mapping(address => Group) groups;
        mapping(address => YieldState) yieldStates;
        mapping(uint32 => YieldRate[]) yieldRates;
    }

    function _yieldStreamerStorage() internal pure returns (YieldStreamerStorageLayout storage $) {
        assembly {
            $.slot := _YIELD_STREAMER_PRIMARY_STORAGE_LOCATION
        }
    }
}
