// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IYieldStreamerTypes } from "./interfaces/IYieldStreamerTypes.sol";

/**
 * @title YieldStreamerStorage_Constants contract
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev The contract that defines the constants used by the yield streamer.
 */
contract YieldStreamerStorage_Constants {
    /// @dev The factor that is used to calculate the yield rate.
    ///      e.g. 0.1% rate should be represented as 0.001*RATE_FACTOR.
    uint240 public constant RATE_FACTOR = 10 ** 9;

    /// @dev The coefficient used to round the yield, fee and other related values
    ///      e.g. value `12345678` will be rounded upward to `12350000` and down to `12340000`
    uint256 public constant ROUND_FACTOR = 10000;

    /// @dev The fee rate that is used to calculate the fee amount.
    ///      e.g. 0.1% rate should be represented as 0.001*RATE_FACTOR.
    uint240 public constant FEE_RATE = 0;

    /// @dev The negative time shift of a day in seconds.
    uint256 public constant NEGATIVE_TIME_SHIFT = 0;

    /// @dev The minimum amount that is allowed to be claimed.
    uint256 public constant MIN_CLAIM_AMOUNT = 1000000;

    /// @dev Whether yield state auto initialization is enabled.
    bool public constant ENABLE_YIELD_STATE_AUTO_INITIALIZATION = false;
}

/**
 * @title YieldStreamerStorage_Initialization contract
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev The contract that defines the initialization storage for the yield streamer.
 */
contract YieldStreamerStorage_Initialization {
    /// @dev The storage location of the yield streamer initialization contract.
    ///      keccak256(abi.encode(uint256(keccak256("cloudwalk.yieldstreamer.initialization.storage")) - 1))) & ~uint256(0xff)
    bytes32 private constant _YIELD_STREAMER_INITIALIZATION_STORAGE_LOCATION =
        0xe30574a965b6970db31584ac81d5a366c5ee7e44e3db18d7f307802e0605a400;

    /// @custom:storage-location erc7201:cloudwalk.yieldstreamer.initialization.storage
    struct YieldStreamerInitializationStorageLayout {
        address sourceYieldStreamer;
        mapping(bytes32 => uint256) groupIds;
    }

    /// @dev The function to access the namespaced storage.
    /// @return $ The yield streamer storage layout, see {YieldStreamerStorageLayout}.
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

/**
 * @title YieldStreamerStorage_Common contract
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev The contract that defines the common storage for the yield streamer.
 */
contract YieldStreamerStorage_Common is IYieldStreamerTypes {
    /// @dev The storage location of the yield streamer primary contract.
    ///      keccak256(abi.encode(uint256(keccak256("cloudwalk.yieldstreamer.primary.storage")) - 1))) & ~uint256(0xff)
    bytes32 private constant _YIELD_STREAMER_STORAGE_LOCATION =
        0x3ffa2d1fa1d7e119f4100ba678d1140b9dc5cebd13fdaaded481a6cf43d1a800;

    /// @custom:storage-location erc7201:cloudwalk.yieldstreamer.primary.storage
    struct YieldStreamerStorageLayout {
        address underlyingToken;
        address feeReceiver;
        mapping(address => Group) groups;
        mapping(address => YieldState) yieldStates;
        mapping(uint32 => YieldRate[]) yieldRates;
    }

    /// @dev The function to access the namespaced storage.
    /// @return $ The yield streamer storage layout, see {YieldStreamerStorageLayout}.
    function _yieldStreamerStorage() internal pure returns (YieldStreamerStorageLayout storage $) {
        assembly {
            $.slot := _YIELD_STREAMER_STORAGE_LOCATION
        }
    }
}

/**
 * @title YieldStreamerStorage contract
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev The contract that combines the constants, common and initialization storage for the yield streamer.
 */
contract YieldStreamerStorage is
    YieldStreamerStorage_Constants,
    YieldStreamerStorage_Common,
    YieldStreamerStorage_Initialization
{

}
