// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title IYieldStreamerInitialization_Types interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the types used in the yield streamer initialization contract.
 */
interface IYieldStreamerInitialization_Types {
    /**
     * @dev Enum that represents the initialization mode.
     *
     * Values:
     *  - Uninitialized: -- The yield state was not initialized.
     *  - Automatic: ------ The yield state was initialized automatically.
     *  - Manual: --------- The yield state was initialized manually.
     */
    enum InitializationMode {
        Uninitialized,
        Automatic,
        Manual
    }

    /**
     * @dev Structure that represents a range of values.
     *
     * Fields:
     *  - mode: ------------ The initialization mode.
     *  - timestamp: ------- The timestamp of the initialization.
     */
    struct InitializationState {
        InitializationMode mode;
        uint64 timestamp;
    }
}

/**
 * @title IYieldStreamerInitialization_Errors interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the errors used in the yield streamer initialization contract.
 */
interface IYieldStreamerInitialization_Errors {
    /// @dev Thrown when the array is empty.
    error YieldStreamer_EmptyArray();

    /// @dev Thrown when the array length is invalid.
    error YieldStreamer_InvalidArrayLength();
}

/**
 * @title IYieldStreamerInitialization_Events interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the events used in the yield streamer initialization contract.
 */
interface IYieldStreamerInitialization_Events {
    /**
     * @dev Emitted when the yield state initialization failed.
     * @param account The account that failed to initialize the yield state.
     * @param reason The reason for the failure (optional).
     * @param code The code of the failure (optional).
     * @param data The data of the failure (optional).
     */
    event YieldStreamer_YieldStateInitializationFailed(
        address indexed account, // Tools: this comment prevents Prettier from formatting into a single line.
        string reason,
        uint256 code,
        bytes data
    );

    /**
     * @dev Emitted when the yield state was initialized.
     * @param account The account that was initialized.
     * @param yield The yield that was initialized.
     */
    event YieldStreamer_YieldStateInitialized(address indexed account, uint256 yield);

    /**
     * @dev Emitted when the source yield streamer was changed.
     * @param oldSourceYieldStreamer The old source yield streamer.
     * @param newSourceYieldStreamer The new source yield streamer.
     */
    event YieldStreamer_SourceYieldStreamerChanged(
        address indexed oldSourceYieldStreamer,
        address indexed newSourceYieldStreamer
    );
}

/**
 * @title IYieldStreamerInitialization_Functions interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the functions used in the yield streamer initialization contract.
 */
interface IYieldStreamerInitialization_Functions {
    function initializeYieldState(address[] memory accounts) external;

    function initializeYieldState(address[] memory accounts, uint256[] memory yields) external;

    function setSourceYieldStreamer(address sourceYieldStreamer) external;
}

/**
 * @title IYieldStreamerInitialization interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the interface for the yield streamer initialization contract
 *      by combining the types, errors, events and functions interfaces.
 */
interface IYieldStreamerInitialization is
    IYieldStreamerInitialization_Types,
    IYieldStreamerInitialization_Errors,
    IYieldStreamerInitialization_Events,
    IYieldStreamerInitialization_Functions
{

}
