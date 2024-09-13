// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

/**
 * @title IYieldStreamer interface
 * @author CloudWalk Inc.
 * @notice The interface of a contract that supports yield streaming
 */
interface IYieldStreamer {
    /**
     * @notice Emitted when an account claims accrued yield
     * @param account The address of the account
     * @param yield The amount of yield before fee
     * @param fee The yield fee
     */
    event Claim(address indexed account, uint256 yield, uint256 fee);

    /**
     * @notice Emitted when yield is accrued for an account
     * @param account The address of the account for which yield is accrued
     * @param nextStash The updated accrued yield amount for the account
     * @param prevStash The previous accrued yield amount for the account
     * @param nextClaimDay The index of the first day from which the yield will be calculated next time
     * @param firstYieldDay The index of the first day from which the yield was calculated for this accrual
     * @param nextClaimDebit The yield amount already claimed for the first day of the next claim
     * @param prevClaimDebit The yield amount claimed previously for the first day of this accrual
     */
    event YieldAccrued(
        address indexed account,
        uint256 nextStash,
        uint256 prevStash,
        uint256 nextClaimDay,
        uint256 firstYieldDay,
        uint256 nextClaimDebit,
        uint256 prevClaimDebit
    );

    /**
     * @notice Structure representing the result of a yield claim operation
     */
    struct ClaimResult {
        uint256 nextClaimDay;   // The index of the first day from which the yield will be calculated next time
        uint256 nextClaimDebit; // The amount of yield already claimed for the first day of the next claim
        uint256 firstYieldDay;  // The index of the first day from which the current yield was calculated for this claim
        uint256 prevClaimDebit; // The amount of yield that was already claimed previously for the first yield day
        uint256 primaryYield;   // The yield primary amount based on the whole days passed since the previous claim
        uint256 streamYield;    // The yield stream amount based on the time passed since the start of the current day
        uint256 lastDayYield;   // The whole-day yield for the last day in the time range of this claim
        uint256 shortfall;      // The amount of yield that is not enough to cover this claim
        uint256 fee;            // The amount of fee for this claim, rounded upward
        uint256 yield;          // The amount of final yield for this claim before applying the fee, rounded down
        uint256 nextStash;      // The remaining accrued yield for the next claim
        uint256 prevStash;      // The previously accrued yield before this claim
    }

    /**
     * @notice Claims a portion of accrued yield
     * @param amount The portion of yield to be claimed
     * @dev Emits a {Claim} event
     */
    function claim(uint256 amount) external;

    /**
     * @notice Accrues all available yield until the beginning of yesterday for a batch of accounts
     *
     * The accrued yield is stored internally for future claims
     *
     * @param accounts The addresses of the accounts to accrue yield for
     * @dev Emits a {YieldAccrued} event for each account
     */
    function accrueBatch(address[] calldata accounts) external;

    /**
     * @notice Provides a preview of the result of claiming all accrued yield for an account
     *
     * @param account The address of the account to preview the claim for
     */
    function claimAllPreview(address account) external view returns (ClaimResult memory);

    /**
     * @notice Provides a preview of the result of claiming a portion of accrued yield for an account
     *
     * @param account The address of the account to preview the claim for
     * @param amount The portion of yield to be claimed
     */
    function claimPreview(address account, uint256 amount) external view returns (ClaimResult memory);
}
