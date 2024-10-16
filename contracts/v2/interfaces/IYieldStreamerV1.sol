// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title IYieldStreamerV1 interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Interface for the version 1 of the yield streamer contract.
 * Provides functions to interact with and retrieve information from the version 1 contract.
 */
interface IYieldStreamerV1 {
    /**
     * @dev Structure containing details of a yield claim operation.
     * Provides all necessary information about the yield accrued and any fees or shortfalls.
     *
     * Fields:
     * - `nextClaimDay`: The index of the day from which yield calculation will continue after this claim.
     * - `nextClaimDebit`: The amount of yield that will be considered already claimed on `nextClaimDay`.
     * - `firstYieldDay`: The index of the first day included in this yield calculation.
     * - `prevClaimDebit`: The amount of yield already claimed on `firstYieldDay` before this claim.
     * - `primaryYield`: The total yield accrued over full days since the previous claim.
     * - `streamYield`: The yield accrued based on the time elapsed in the current day since the last claim.
     * - `lastDayPartialYield`: The yield for the partial last day in the claim period.
     * - `shortfall`: The amount by which the available yield is insufficient to cover the claim (if any).
     * - `fee`: The fee amount applied to this claim (rounded upward).
     * - `yield`: The net yield amount for this claim after fees (rounded down).
     */
    struct ClaimResult {
        uint256 nextClaimDay;
        uint256 nextClaimDebit;
        uint256 firstYieldDay;
        uint256 prevClaimDebit;
        uint256 primaryYield;
        uint256 streamYield;
        uint256 lastDayPartialYield;
        uint256 shortfall;
        uint256 fee;
        uint256 yield;
    }

    /**
     * @dev Provides a preview of the result of claiming all accrued yield for an account.
     * Calculates the yield that would be claimed without modifying the contract state.
     *
     * @param account The address of the account for which to preview the claim.
     * @return A `ClaimResult` struct containing detailed information about the potential claim.
     */
    function claimAllPreview(address account) external view returns (ClaimResult memory);

    /**
     * @dev Adds an account to the blocklist, preventing it from interacting with certain functions.
     * Used to restrict accounts from participating in yield accrual or claims.
     *
     * @param account The address of the account to add to the blocklist.
     */
    function blocklist(address account) external;

    /**
     * @dev Checks whether an account is configured as a blocklister.
     * Blocklisters have permissions to manage the blocklist of the yield streamer.
     *
     * @param account The address of the account to check.
     * @return True if the account has blocklister permissions, false otherwise.
     */
    function isBlocklister(address account) external view returns (bool);

    /**
     * @dev Retrieves the group key associated with a specific account.
     * Group keys are used to assign accounts to groups with different yield rates or configurations.
     *
     * @param account The address of the account for which to retrieve the group key.
     * @return The group key (`bytes32`) associated with the given account.
     */
    function getAccountGroup(address account) external view returns (bytes32);
}
