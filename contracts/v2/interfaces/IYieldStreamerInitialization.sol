// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title IYieldStreamerInitialization_Errors interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the errors used in the yield streamer initialization contract.
 */
interface IYieldStreamerInitialization_Errors {
    /// @dev Thrown when the array is empty.
    error YieldStreamer_EmptyArray();

    /// @dev Thrown when an account is already initialized.
    error YieldStreamer_AccountAlreadyInitialized(address account);

    /// @dev Thrown when account initialization is prohibited.
    error YieldStreamer_AccountInitializationProhibited(address account);

    /// @dev Thrown when the source yield streamer is not configured.
    error YieldStreamer_SourceYieldStreamerNotConfigured();

    /// @dev Thrown when the source yield streamer is already configured.
    error YieldStreamer_SourceYieldStreamerAlreadyConfigured();

    /// @dev Thrown when the source yield streamer group is already mapped.
    error YieldStreamer_SourceYieldStreamerGroupAlreadyMapped();

    /// @dev Thrown when this contract is not authorized to blocklist accounts on the source yield streamer.
    error YieldStreamer_SourceYieldStreamerUnauthorizedBlocklister();
}

/**
 * @title IYieldStreamerInitialization_Events interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the events used in the yield streamer initialization contract.
 */
interface IYieldStreamerInitialization_Events {
    /**
     * @dev Emitted when an account is initialized.
     * @param account The account that was initialized.
     * @param groupId The group id that the account was assigned to.
     * @param accountBalance The balance of the account at the time of initialization.
     * @param accruedYield The accrued yield of the account at the time of initialization.
     * @param streamYield The stream yield of the account at the time of initialization.
     */
    event YieldStreamer_AccountInitialized(
        address indexed account,
        uint256 indexed groupId,
        uint256 accountBalance,
        uint256 accruedYield,
        uint256 streamYield
    );

    /**
     * @dev Emitted when the source yield streamer was changed.
     * @param oldSourceYieldStreamer The old source yield streamer.
     * @param newSourceYieldStreamer The new source yield streamer.
     */
    event YieldStreamer_SourceYieldStreamerChanged(
        address indexed oldSourceYieldStreamer,
        address indexed newSourceYieldStreamer
    );

    /**
     * @dev Emitted when a source yield streamer group is mapped.
     * @param groupKey The group key that was mapped.
     * @param newGroupId The new group id that was mapped.
     * @param oldGroupId The old group id that was mapped.
     */
    event YieldStreamer_GroupMapped(
        bytes32 groupKey, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 newGroupId,
        uint256 oldGroupId
    );

    /**
     * @dev Emitted when the initialized flag is set manually.
     * @param account The account that the initialized flag is set for.
     * @param isInitialized The initialized flag value.
     */
    event YieldStreamer_InitializedFlagSet(address indexed account, bool isInitialized);
}

/**
 * @title IYieldStreamerInitialization_Functions interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the functions used in the yield streamer initialization contract.
 */
interface IYieldStreamerInitialization_Functions {
    /**
     * @dev Initializes multiple accounts.
     * @param accounts The accounts to initialize.
     */
    function initializeAccounts(address[] calldata accounts) external;

    /**
     * @dev Sets the initialized state for an account.
     * @param account The account to set the initialized state for.
     * @param isInitialized The initialized state to set.
     */
    function setInitializedFlag(address account, bool isInitialized) external;

    /**
     * @dev Sets the source yield streamer.
     * @param sourceYieldStreamer The source yield streamer to set.
     */
    function setSourceYieldStreamer(address sourceYieldStreamer) external;

    /**
     * @dev Maps a source yield streamer group.
     * @param groupKey The group key to map.
     * @param groupId The group id to map.
     */
    function mapSourceYieldStreamerGroup(bytes32 groupKey, uint256 groupId) external;

    /**
     * @dev Returns the source yield streamer address.
     */
    function sourceYieldStreamer() external view returns (address);
}

/**
 * @title IYieldStreamerInitialization interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the interface for the yield streamer initialization contract
 *      by combining the types, errors, events and functions interfaces.
 */
interface IYieldStreamerInitialization is
    IYieldStreamerInitialization_Errors,
    IYieldStreamerInitialization_Events,
    IYieldStreamerInitialization_Functions
{

}
