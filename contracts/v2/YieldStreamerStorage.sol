// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IYieldStreamerTypes } from "./interfaces/IYieldStreamerTypes.sol";
import { IYieldStreamerInitialization_Types } from "./interfaces/IYieldStreamerInitialization.sol";

contract YieldStreamerStorage_Constants {
    uint256 public constant ROUND_FACTOR = 10000;

    uint240 public constant FEE_RATE = 0;

    uint240 public constant RATE_FACTOR = 10 ** 9;

    uint256 public constant NEGATIVE_TIME_SHIFT = 0;

    uint256 public constant MIN_CLAIM_AMOUNT = 1000000;
}

contract YieldStreamerStorage_Initialization {
    bytes32 private constant _YIELD_STREAMER_INITIALIZATION_STORAGE_LOCATION =
        0xe30574a965b6970db31584ac81d5a366c5ee7e44e3db18d7f307802e0605a400;

    /// @custom:storage-location cloudwalk.yieldstreamer.initialization.storage
    struct YieldStreamerInitializationStorageLayout {
        address sourceYieldStreamer;
        mapping(address => IYieldStreamerInitialization_Types.InitializationState) initializationStates;
    }

    function _yieldStreamerInitializationStorage()
        internal
        pure
        returns (YieldStreamerInitializationStorageLayout storage $)
    {
        assembly {
            $.slot := _YIELD_STREAMER_INITIALIZATION_STORAGE_LOCATION
        }
    }
}

contract YieldStreamerStorage_Common is IYieldStreamerTypes {
    bytes32 private constant _YIELD_STREAMER_STORAGE_LOCATION =
        0x3ffa2d1fa1d7e119f4100ba678d1140b9dc5cebd13fdaaded481a6cf43d1a800;

    /// @custom:storage-location cloudwalk.yieldstreamer.primary.storage
    struct YieldStreamerStorageLayout {
        address underlyingToken;
        address feeReceiver;
        mapping(address => Group) groups;
        mapping(address => YieldState) yieldStates;
        mapping(uint32 => YieldRate[]) yieldRates;
    }

    function _yieldStreamerStorage() internal pure returns (YieldStreamerStorageLayout storage $) {
        assembly {
            $.slot := _YIELD_STREAMER_STORAGE_LOCATION
        }
    }
}

contract YieldStreamerStorage is
    YieldStreamerStorage_Constants,
    YieldStreamerStorage_Common,
    YieldStreamerStorage_Initialization
{}
