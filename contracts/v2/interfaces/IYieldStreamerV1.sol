// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IYieldStreamerV1 {
    /**
     * @notice A structure describing the result details of a claim operation
     */
    struct ClaimResult {
        uint256 nextClaimDay;   // The index of the day from which the subsequent yield will be calculated next time
        uint256 nextClaimDebit; // The amount of yield that will already be considered claimed for the next claim day
        uint256 firstYieldDay;  // The index of the first day from which the current yield was calculated for this claim
        uint256 prevClaimDebit; // The amount of yield that was already claimed previously for the first yield day
        uint256 primaryYield;   // The yield primary amount based on the number of whole days passed since the previous claim
        uint256 streamYield;    // The yield stream amount based on the time passed since the beginning of the current day
        uint256 lastDayYield;   // The whole-day yield for the last day in the time range of this claim
        uint256 shortfall;      // The amount of yield that is not enough to cover this claim
        uint256 fee;            // The amount of fee for this claim, rounded upward
        uint256 yield;          // The amount of final yield for this claim before applying the fee, rounded down
    }

    /**
     * @notice Previews the result of claiming all accrued yield
     *
     * @param account The address to preview the claim for
     */
    function claimAllPreview(address account) external view returns (ClaimResult memory);
}
