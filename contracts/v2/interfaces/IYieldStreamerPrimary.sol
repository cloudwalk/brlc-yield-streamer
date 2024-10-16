// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IYieldStreamerTypes } from "./IYieldStreamerTypes.sol";

/**
 * @title IYieldStreamerPrimary_Errors interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the custom errors used by the yield streamer primary contract.
 */
interface IYieldStreamerPrimary_Errors {
    /// @dev Thrown when the provided time range for yield calculation is invalid.
    error YieldStreamer_TimeRangeInvalid();

    /// @dev Thrown when an account does not have enough yield balance to complete an operation.
    error YieldStreamer_YieldBalanceInsufficient();

    /// @dev Thrown when a function is called by an unauthorized address, specifically in hooks.
    error YieldStreamer_HookCallerUnauthorized();

    /// @dev Thrown when the claim amount is not a properly rounded down value.
    error YieldStreamer_ClaimAmountNonRounded();

    /// @dev Thrown when the claim amount is below the minimum allowed amount.
    error YieldStreamer_ClaimAmountBelowMinimum();

    /// @dev Thrown when the fee receiver address is not configured but required for an operation.
    error YieldStreamer_FeeReceiverNotConfigured();

    /// @dev Thrown when an operation is attempted on an account that has not been initialized.
    error YieldStreamer_AccountNotInitialized();
}

/**
 * @title IYieldStreamerPrimary_Events interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the events emitted by the yield streamer primary contract.
 */
interface IYieldStreamerPrimary_Events {
    /**
     * @dev Emitted when yield is accrued for an account.
     *
     * @param account The address of the account for which yield was accrued.
     * @param newAccruedYield The new total accrued yield after accrual.
     * @param newStreamYield The new stream yield after accrual.
     * @param oldAccruedYield The previous accrued yield before accrual.
     * @param oldStreamYield The previous stream yield before accrual.
     */
    event YieldStreamer_YieldAccrued(
        address indexed account,
        uint256 newAccruedYield,
        uint256 newStreamYield,
        uint256 oldAccruedYield,
        uint256 oldStreamYield
    );

    /**
     * @dev Emitted when yield is transferred to an account as a result of a claim.
     *
     * @param account The address of the account receiving the yield.
     * @param yield The amount of yield transferred to the account after fees.
     * @param fee The amount of fee deducted from the yield.
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
 * @dev Defines the function signatures for the yield streamer primary contract.
 */
interface IYieldStreamerPrimary_Functions {
    /**
     * @dev Claims a specific amount of yield for the given account.
     * Transfers the specified amount of yield (after fees) to the account.
     *
     * @param account The address of the account for which to claim yield.
     * @param amount The amount of yield to claim.
     */
    function claimAmountFor(address account, uint256 amount) external;

    /**
     * @dev Retrieves the current yield state for a given account.
     * Provides information about the account's yield accrual and balances.
     *
     * @param account The address of the account to query.
     * @return A `YieldState` struct containing the account's yield state.
     */
    function getYieldState(address account) external view returns (IYieldStreamerTypes.YieldState memory);

    /**
     * @dev Provides a preview of the claimable yield for a given account at the current time.
     * Estimates the yield amount that can be claimed without modifying the contract state.
     *
     * @param account The address of the account to query.
     * @return A `ClaimPreview` struct containing details of the claimable yield.
     */
    function getClaimPreview(address account) external view returns (IYieldStreamerTypes.ClaimPreview memory);

    /**
     * @dev Provides a preview of the yield accrual for a given account over time.
     * Estimates how the yield will accrue based on current rates without modifying the state.
     *
     * @param account The address of the account to query.
     * @return An `AccruePreview` struct containing details of the accrued yield.
     */
    function getAccruePreview(address account) external view returns (IYieldStreamerTypes.AccruePreview memory);

    /**
     * @dev Retrieves the array of yield rates associated with a specific group ID.
     *
     * @param groupId The ID of the group to query.
     * @return An array of `YieldRate` structs representing the group's yield rates.
     */
    function getGroupYieldRates(uint256 groupId) external view returns (IYieldStreamerTypes.YieldRate[] memory);

    /**
     * @dev Retrieves the group ID to which a specific account is assigned.
     *
     * @param account The address of the account to query.
     * @return The group ID of the account.
     */
    function getAccountGroup(address account) external view returns (uint256);

    /**
     * @dev Returns the address of the underlying token used by the yield streamer.
     *
     * @return The address of the underlying ERC20 token contract.
     */
    function underlyingToken() external view returns (address);

    /**
     * @dev Returns the address of the fee receiver configured in the yield streamer.
     *
     * @return The address of the fee receiver.
     */
    function feeReceiver() external view returns (address);

    /**
     * @dev Returns the current block timestamp as used by the contract.
     * May include adjustments such as negative time shifts.
     *
     * @return The current block timestamp.
     */
    function blockTimestamp() external view returns (uint256);
}

/**
 * @title IYieldStreamerPrimary interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the interface for the yield streamer primary contract
 * by combining the types, errors, events and functions interfaces.
 */
interface IYieldStreamerPrimary is
    IYieldStreamerPrimary_Errors,
    IYieldStreamerPrimary_Events,
    IYieldStreamerPrimary_Functions
{
    // Empty interface to combine errors, events, and functions
}
