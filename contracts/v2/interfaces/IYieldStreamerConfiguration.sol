// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title IYieldStreamerConfiguration_Errors interface
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev Defines the errors used in the yield streamer configuration contract.
 */
interface IYieldStreamerConfiguration_Errors {
    /// @dev Thrown when the yield rate item index is invalid.
    error YieldStreamer_YieldRateInvalidItemIndex();

    /// @dev Thrown when the yield rate effective day is invalid.
    error YieldStreamer_YieldRateInvalidEffectiveDay();

    /// @dev Thrown when the yield rate is already configured.
    error YieldStreamer_YieldRateAlreadyConfigured();

    /// @dev Thrown when the fee receiver is already configured.
    error YieldStreamer_FeeReceiverAlreadyConfigured();

    /// @dev Thrown when the group is already assigned.
    error YieldStreamer_GroupAlreadyAssigned(address account);
}

/**
 * @title IYieldStreamerConfiguration_Events interface
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev Defines the events used in the yield streamer configuration contract.
 */
interface IYieldStreamerConfiguration_Events {
    /**
     * @dev Emitted when a group is assigned to an account.
     * @param account The account that the group is assigned to.
     * @param newGroupId The new group ID.
     * @param oldGroupId The old group ID.
     */
    event YieldStreamer_GroupAssigned(
        address indexed account, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 indexed newGroupId,
        uint256 indexed oldGroupId
    );

    /**
     * @dev Emitted when a new yield rate is added.
     * @param groupId The group ID yield rate is added to.
     * @param effectiveDay The effective day.
     * @param rateValue The rate value.
     */
    event YieldStreamer_YieldRateAdded(
        uint256 indexed groupId, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 effectiveDay,
        uint256 rateValue
    );

    /**
     * @dev Emitted when a yield rate is updated.
     * @param groupId The group ID yield rate is updated for.
     * @param itemIndex The item index of the yield rate.
     * @param effectiveDay The effective day.
     * @param rateValue The rate value.
     */
    event YieldStreamer_YieldRateUpdated(
        uint256 indexed groupId,
        uint256 itemIndex,
        uint256 effectiveDay,
        uint256 rateValue
    );

    /**
     * @dev Emitted when the fee receiver is changed.
     * @param newFeeReceiver The new fee receiver.
     * @param oldFeeReceiver The old fee receiver.
     */
    event YieldStreamer_FeeReceiverChanged(
        address indexed newFeeReceiver, // Tools: this comment prevents Prettier from formatting into a single line.
        address indexed oldFeeReceiver
    );
}

/**
 * @title IYieldStreamerConfiguration_Functions interface
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev Defines the functions used in the yield streamer configuration contract.
 */
interface IYieldStreamerConfiguration_Functions {
    /**
     *  @dev Adds a new yield rate to the yield streamer.
     *
     * Emits:
     *  - {YieldStreamer_YieldRateAdded}
     *
     * @param groupId The ID of the group to add the yield rate to.
     * @param effectiveDay The effective day of the yield rate.
     * @param rateValue The value of the yield rate.
     */
    function addYieldRate(uint256 groupId, uint256 effectiveDay, uint256 rateValue) external;

    /**
     * @dev Updates a yield rate in the yield streamer.
     *
     * Emits:
     *  - {YieldStreamer_YieldRateUpdated}
     *
     * @param groupId The ID of the group to update the yield rate for.
     * @param itemIndex The index of the yield rate to update.
     * @param effectiveDay The effective day of the yield rate.
     * @param rateValue The value of the yield rate.
     */
    function updateYieldRate(uint256 groupId, uint256 itemIndex, uint256 effectiveDay, uint256 rateValue) external;

    /**
     * @dev Assigns a group to the accounts.
     *
     * Emits:
     *  - {YieldStreamer_GroupAssigned}
     *
     * @param groupId The ID of the group to assign.
     * @param accounts The accounts to assign to the group.
     * @param forceYieldAccrue Whether to accrue yield for the accounts.
     */
    function assignGroup(uint256 groupId, address[] memory accounts, bool forceYieldAccrue) external;

    /**
     * @dev Sets the fee receiver for the yield streamer.
     *
     * Emits:
     *  - {YieldStreamer_FeeReceiverChanged}
     *
     * @param newFeeReceiver The new fee receiver.
     */
    function setFeeReceiver(address newFeeReceiver) external;
}

/**
 * @title IYieldStreamerConfiguration interface
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev Defines the interface for the yield streamer configuration contract
 *      by combining the errors, events and functions interfaces.
 */
interface IYieldStreamerConfiguration is
    IYieldStreamerConfiguration_Errors,
    IYieldStreamerConfiguration_Events,
    IYieldStreamerConfiguration_Functions
{

}
