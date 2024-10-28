// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IYieldStreamerTypes } from "./interfaces/IYieldStreamerTypes.sol";

/**
 * @title YieldStreamerStorage_Constants contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Contains constant values for the yield streamer contract.
 */
contract YieldStreamerStorage_Constants {
    /**
     * @dev The factor used to scale yield rates for precision.
     * For example, a 0.1% rate should be represented as 0.001 * RATE_FACTOR.
     */
    uint240 public constant RATE_FACTOR = 10 ** 9;

    /**
     * @dev The factor used for rounding yield, fees, and other related values.
     * For example, a value of `12345678` will be rounded up to `12350000` and down to `12340000`.
     */
    uint256 public constant ROUND_FACTOR = 10000;

    /**
     * @dev The fee rate used to calculate fee amounts during yield claims.
     * For example, a 0.1% fee rate should be represented as 0.001 * RATE_FACTOR.
     */
    uint240 public constant FEE_RATE = 0;

    /**
     * @dev The negative time shift applied to timestamps, measured in seconds.
     * Used to adjust the effective time for yield calculations.
     */
    uint256 public constant NEGATIVE_TIME_SHIFT = 3 hours;

    /**
     * @dev The minimum amount of yield that can be claimed in a single operation.
     */
    uint256 public constant MIN_CLAIM_AMOUNT = 1000000;

    /**
     * @dev Flag indicating whether automatic initialization of yield states is enabled.
     */
    bool public constant ENABLE_YIELD_STATE_AUTO_INITIALIZATION = false;
}

/**
 * @title YieldStreamerStorage_Initialization contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the initialization storage layout for the yield streamer contract.
 */
contract YieldStreamerStorage_Initialization {
    /**
     * @dev The storage slot location for the yield streamer initialization data.
     * Calculated as:
     * keccak256(abi.encode(uint256(keccak256("cloudwalk.yieldstreamer.initialization.storage")) - 1)) & ~uint256(0xff)
     */
    bytes32 private constant _YIELD_STREAMER_INITIALIZATION_STORAGE_LOCATION =
        0xe30574a965b6970db31584ac81d5a366c5ee7e44e3db18d7f307802e0605a400;

    /**
     * @dev Structure representing the storage layout for the initialization-specific data.
     *
     * Fields:
     * - `sourceYieldStreamer`: The address of the source yield streamer contract used during initialization.
     * - `groupIds`: A mapping from group keys in the source yield streamer to group IDs in this contract.
     *
     * @custom:storage-location erc7201:cloudwalk.yieldstreamer.initialization.storage
     */
    struct YieldStreamerInitializationStorageLayout {
        address sourceYieldStreamer;
        mapping(bytes32 => uint256) groupIds;
    }

    /**
     * @dev Provides access to the storage layout for yield streamer initialization.
     * Uses a specific storage slot to prevent conflicts with other contracts.
     *
     * @return $ A storage pointer to the YieldStreamerInitializationStorageLayout struct.
     */
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
 * @title YieldStreamerStorage_Primary contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the primary storage layout for the yield streamer contract.
 */
contract YieldStreamerStorage_Primary is IYieldStreamerTypes {
    /**
     * @dev The storage slot location for the primary yield streamer data.
     * Calculated as:
     * keccak256(abi.encode(uint256(keccak256("cloudwalk.yieldstreamer.primary.storage")) - 1)) & ~uint256(0xff)
     */
    bytes32 private constant _YIELD_STREAMER_STORAGE_LOCATION =
        0x3ffa2d1fa1d7e119f4100ba678d1140b9dc5cebd13fdaaded481a6cf43d1a800;

    /**
     * @dev Structure representing the storage layout for the primary yield streamer data.
     *
     * Fields:
     * - `underlyingToken`: The address of the underlying token contract used for yield calculations.
     * - `feeReceiver`: The address of the fee receiver for any fees collected during yield claims.
     * - `groups`: A mapping from account addresses to their assigned group.
     * - `yieldStates`: A mapping from account addresses to their yield state.
     * - `yieldRates`: A mapping from group IDs to arrays of yield rates applied to that group.
     *
     * @custom:storage-location erc7201:cloudwalk.yieldstreamer.primary.storage
     */
    struct YieldStreamerStorageLayout {
        address underlyingToken;
        address feeReceiver;
        mapping(address => Group) groups;
        mapping(address => YieldState) yieldStates;
        mapping(uint32 => YieldTieredRate[]) yieldRates;
    }

    /**
     * @dev Provides access to the primary storage layout for the yield streamer.
     * Uses a specific storage slot to prevent conflicts with other contracts.
     *
     * @return $ A storage pointer to the YieldStreamerStorageLayout struct.
     */
    function _yieldStreamerStorage() internal pure returns (YieldStreamerStorageLayout storage $) {
        assembly {
            $.slot := _YIELD_STREAMER_STORAGE_LOCATION
        }
    }
}

/**
 * @title YieldStreamerStorage contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Combines the constants, primary storage, and initialization storage into a single contract.
 */
contract YieldStreamerStorage is
    YieldStreamerStorage_Constants,
    YieldStreamerStorage_Primary,
    YieldStreamerStorage_Initialization
{
    // Empty contract to combine the constants, primary storage, and initialization storage
}
