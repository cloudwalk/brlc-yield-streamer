// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IYieldStreamerTypes } from "./IYieldStreamerTypes.sol";

/**
 * @title IYieldStreamerPrimary interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the errors used in the yield streamer primary contract.
 */
interface IYieldStreamerPrimary_Errors {
    /// @dev Thrown when the time range is invalid.
    error YieldStreamer_TimeRangeInvalid();

    /// @dev Thrown when the yield balance is insufficient.
    error YieldStreamer_YieldBalanceInsufficient();

    /// @dev Thrown when the hook caller is unauthorized.
    error YieldStreamer_HookCallerUnauthorized();

    /// @dev Thrown when the claim amount is not rounded.
    error YieldStreamer_ClaimAmountNonRounded();

    /// @dev Thrown when the claim amount is below the minimum.
    error YieldStreamer_ClaimAmountBelowMinimum();

    /// @dev Thrown when the fee receiver is not configured.
    error YieldStreamer_FeeReceiverNotConfigured();

    /// @dev Thrown when the account is not initialized.
    error YieldStreamer_AccountNotInitialized();
}

/**
 * @title IYieldStreamerPrimary_Events interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the events used in the yield streamer primary contract.
 */
interface IYieldStreamerPrimary_Events {
    /**
     * @dev Emitted when the yield is accrued for an account.
     * @param account The account the yield was accrued for.
     * @param newAccruedYield The new accrued yield.
     * @param newStreamYield The new stream yield.
     * @param oldAccruedYield The old accrued yield.
     * @param oldStreamYield The old stream yield.
     */
    event YieldStreamer_YieldAccrued(
        address indexed account,
        uint256 newAccruedYield,
        uint256 newStreamYield,
        uint256 oldAccruedYield,
        uint256 oldStreamYield
    );

    /**
     * @dev Emitted when the yield is transferred to an account.
     * @param account The account the yield was transferred to.
     * @param yield The amount of yield transferred.
     * @param fee The amount of fee transferred.
     */
    event YieldStreamer_YieldTransferred(
        address indexed account, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 yield,
        uint256 fee
    );
}

/**
 * @title IYieldStreamerPrimary_Functions interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the functions used in the yield streamer primary contract.
 */
interface IYieldStreamerPrimary_Functions {
    /**
     * @dev Claims the yield for a given account.
     * @param account The account to claim the yield for.
     * @param amount The amount of yield to claim.
     */
    function claimAmountFor(address account, uint256 amount) external;

    /**
     * @dev Gets the yield state for a given account.
     * @param account The account to get the yield state for.
     * @return The yield state.
     */
    function getYieldState(address account) external view returns (IYieldStreamerTypes.YieldState memory);

    /**
     * @dev Gets the claim preview for a given account.
     * @param account The account to get the claim preview for.
     * @return The claim preview.
     */
    function getClaimPreview(address account) external view returns (IYieldStreamerTypes.ClaimPreview memory);

    /**
     * @dev Gets the accrue preview for a given account.
     * @param account The account to get the accrue preview for.
     * @return The accrue preview.
     */
    function getAccruePreview(address account) external view returns (IYieldStreamerTypes.AccruePreview memory);

    /**
     * @dev Returns an array of yield rates for a given account group.
     * @param groupId The ID of the group to get the yield rates for.
     * @return The array of yield rates
     */
    function getGroupYieldRates(uint256 groupId) external view returns (IYieldStreamerTypes.YieldRate[] memory);

    /**
     * @dev Returns the group ID for a given account.
     * @param account The account to get the group ID for.
     * @return The group ID.
     */
    function getAccountGroup(address account) external view returns (uint256);

    /**
     * @dev Returns the underlying token contract address.
     */
    function underlyingToken() external view returns (address);

    /**
     * @dev Returns the fee receiver address.
     */
    function feeReceiver() external view returns (address);

    /**
     * @dev Returns the current block timestamp according to the contract settings.
     */
    function blockTimestamp() external view returns (uint256);
}

/**
 * @title IYieldStreamerPrimary interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the interface for the yield streamer primary contract
 *      by combining the errors, events and functions interfaces.
 */
interface IYieldStreamerPrimary is
    IYieldStreamerPrimary_Errors,
    IYieldStreamerPrimary_Events,
    IYieldStreamerPrimary_Functions
{

}
