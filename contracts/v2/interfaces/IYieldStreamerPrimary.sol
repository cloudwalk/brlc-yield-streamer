// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IYieldStreamerTypes } from "./IYieldStreamerTypes.sol";


interface IYieldStreamerPrimary is IYieldStreamerTypes {
    // -------------------- Errors -------------------- //

    error YieldStreamer_InvalidTimeRange();

    error YieldStreamer_InsufficientYieldBalance();

    // -------------------- Events -------------------- //

    event YieldStreamer_YieldAccrued(
        address indexed account,
        uint256 newAccruedYield,
        uint256 newStreamYield,
        uint256 oldAccruedYield,
        uint256 oldStreamYield
    );

    event YieldStreamer_YieldTransferred(
        address indexed account, // Format: prevent collapse
        uint256 accruedYield,
        uint256 streamYield
    );

    // -------------------- Structs -------------------- //

    struct YieldResult {
        uint256 firstDayYield;
        uint256 fullDaysYield;
        uint256 lastDayYield;
    }

    struct YieldBalance {
        uint256 accruedYield;
        uint256 streamYield;
    }

    struct ClaimPreview {
        YieldBalance balance;
        YieldRate[] yieldRates;
        YieldResult[] yieldResults;
    }

    // -------------------- Functions -------------------- //

    function claimAllFor(address account) external;

    function claimAmountFor(address account, uint256 amount) external;

    function getYieldState(address account) external view returns (YieldState memory);

    function getYieldBalance(address account) external view returns (YieldBalance memory);

    function getClaimPreview(address account) external view returns (ClaimPreview memory);
}