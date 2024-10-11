// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IYieldStreamerV1 {
    /**
     * @notice A structure describing the result details of a claim operation
     *
     * The fields:
     *
     * - nextClaimDay ---- The index of the day from which the subsequent yield will be calculated next time.
     * - nextClaimDebit -- The amount of yield that will already be considered claimed for the next claim day.
     * - nextClaimDay ---- The index of the day from which the subsequent yield will be calculated next time
     * - nextClaimDebit -- The amount of yield that will already be considered claimed for the next claim day
     * - firstYieldDay --- The index of the first day from which the current yield was calculated for this claim
     * - prevClaimDebit -- The amount of yield that was already claimed previously for the first yield day
     * - primaryYield ---- The yield primary amount based on the number of whole days passed since the previous claim
     * - streamYield ----- The yield stream amount based on the time passed since the beginning of the current day
     * - lastDayYield ---- The whole-day yield for the last day in the time range of this claim
     * - shortfall ------- The amount of yield that is not enough to cover this claim
     * - fee ------------- The amount of fee for this claim, rounded upward
     * - yield ----------- The amount of final yield for this claim before applying the fee, rounded down
     */
    struct ClaimResult {
        uint256 nextClaimDay;
        uint256 nextClaimDebit;
        uint256 firstYieldDay;
        uint256 prevClaimDebit;
        uint256 primaryYield;
        uint256 streamYield;
        uint256 lastDayYield;
        uint256 shortfall;
        uint256 fee;
        uint256 yield;
    }

    /**
     * @notice Previews the result of claiming all accrued yield
     *
     * @param account The address to preview the claim for
     */
    function claimAllPreview(address account) external view returns (ClaimResult memory);
}
