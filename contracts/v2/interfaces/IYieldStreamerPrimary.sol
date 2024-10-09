// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IYieldStreamerTypes } from "./IYieldStreamerTypes.sol";

interface IYieldStreamerPrimary_Errors {
    // -------------------- Errors -------------------- //

    error YieldStreamer_InvalidTimeRange();

    error YieldStreamer_InsufficientYieldBalance();

    error YieldStreamer_UnauthorizedHookCaller();

    error YieldStreamer_ClaimAmountNonRounded();

    error YieldStreamer_ClaimAmountBelowMinimum();
}

interface IYieldStreamerPrimary_Events {
    // -------------------- Events -------------------- //

    event YieldStreamer_YieldAccrued(
        address indexed account,
        uint256 newAccruedYield,
        uint256 newStreamYield,
        uint256 oldAccruedYield,
        uint256 oldStreamYield
    );

    event YieldStreamer_YieldTransferred(
        address indexed account, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 accruedYield,
        uint256 streamYield
    );
}

interface IYieldStreamerPrimary_Functions {
    // -------------------- Functions -------------------- //

    function claimAmountFor(address account, uint256 amount) external;

    function getYieldState(address account) external view returns (IYieldStreamerTypes.YieldState memory);

    function getClaimPreview(address account) external view returns (IYieldStreamerTypes.ClaimPreview memory);

    function getAccruePreview(address account) external view returns (IYieldStreamerTypes.AccruePreview memory);
}

interface IYieldStreamerPrimary is
    IYieldStreamerPrimary_Errors,
    IYieldStreamerPrimary_Events,
    IYieldStreamerPrimary_Functions
{}
