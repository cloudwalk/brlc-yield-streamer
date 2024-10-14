// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title IYieldStreamerTypes interface
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Defines the types used in the yield streamer contracts.
 */
interface IYieldStreamerTypes {
    /**
     * @dev Enum to represent the possible flag indices of the yield state.
     *
     * Values:
     *  - Initialized: -- The yield state has been initialized.
     */
    enum YieldStateFlagIndex {
        Initialized
    }
    /**
     * @dev Structure to store the group information.
     *
     * Fields:
     *  - id: -- The group id.
     */
    struct Group {
        uint32 id;
        // uint224 __reserved; // Reserved for future use until the end of the storage slot.
    }

    /**
     * @dev Structure to store the yield rate for a specific day.
     *
     * Fields:
     *  - effectiveDay: -- The effective day.
     *  - value: --------- The rate value.
     */
    struct YieldRate {
        uint16 effectiveDay;
        uint32 value;
        // uint208 __reserved; // Reserved for future use until the end of the storage slot.
    }

    /**
     * @dev Structure to store the yield state of an account.
     *
     * Fields:
     *  - flags: ---------------- The flags of the yield state.
     *  - streamYield: ---------- The stream yield.
     *  - accruedYield: --------- The accrued yield.
     *  - lastUpdateTimestamp: -- The timestamp of the last update.
     *  - lastUpdateBalance: ---- The balance at the last update.
     */
    struct YieldState {
        uint8 flags;
        uint64 streamYield;
        uint64 accruedYield;
        uint40 lastUpdateTimestamp;
        uint64 lastUpdateBalance;
        // uint16 __reserved; // Reserved for future use until the end of the storage slot.
    }

    /**
     * @dev Structure to store the claim preview information.
     *
     * Fields:
     *  - yield: ---- The yield amount available that can be claimed.
     *  - fee: ------ The fee amount that will be charged during the claim.
     *  - balance: -- The principal balance after the claim.
     *  - rate: ----- The current yield rate.
     */
    struct ClaimPreview {
        uint256 yield;
        uint256 fee;
        uint256 balance;
        uint256 rate;
    }

    /**
     * @dev Structure to store the accrue preview information for a specific period.
     *
     * Fields:
     *  - fromTimestamp: ------- The timestamp of the start of the period to preview.
     *  - toTimestamp: --------- The timestamp of the end of the period to preview.
     *  - balance: ------------- The balance at the beginning of the period.
     *  - accruedYieldBefore: -- The accrued yield before the operation.
     *  - streamYieldBefore: --- The stream yield before the operation.
     *  - accruedYieldAfter: --- The accrued yield after the operation.
     *  - streamYieldAfter: ---- The stream yield after the operation.
     *  - rates: --------------- The yield rates used to for each sub-period.
     *  - results: ------------- The yield calculation results for each sub-period.
     */
    struct AccruePreview {
        uint256 fromTimestamp;
        uint256 toTimestamp;
        uint256 balance;
        uint256 streamYieldBefore;
        uint256 accruedYieldBefore;
        uint256 streamYieldAfter;
        uint256 accruedYieldAfter;
        YieldRate[] rates;
        YieldResult[] results;
    }

    /**
     * @dev Structure to store the yield calculation result for a specific period.
     *
     * Fields:
     *  - firstDayYield: -- The (partial) yield for the first day of the period.
     *  - fullDaysYield: -- The yield for the full days of the period.
     *  - lastDayYield: --- The (partial) yield for the last day of the period.
     */
    struct YieldResult {
        uint256 firstDayYield;
        uint256 fullDaysYield;
        uint256 lastDayYield;
    }
}
