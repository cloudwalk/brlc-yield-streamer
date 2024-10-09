// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IYieldStreamerConfiguration_Errors {
    // -------------------- Errors -------------------- //

    error YieldStreamer_YieldRateWrongIndex();

    error YieldStreamer_YieldRateInvalidEffectiveDay();

    error YieldStreamer_YieldRateValueAlreadyConfigured();

    error YieldStreamer_GroupAlreadyAssigned(address account);
}

interface IYieldStreamerConfiguration_Events {
    // -------------------- Events -------------------- //

    event YieldStreamer_GroupAssigned(uint256 indexed groupId, address indexed account);

    event YieldStreamer_YieldRateAdded(uint256 indexed groupId, uint256 effectiveDay, uint256 rateValue);

    event YieldStreamer_YieldRateUpdated(
        uint256 indexed groupId,
        uint256 effectiveDay,
        uint256 rateValue,
        uint256 index
    );
}

interface IYieldStreamerConfiguration_Functions {
    // -------------------- Functions -------------------- //

    function assignGroup(uint32 groupId, address[] memory accounts, bool accrueYield) external;

    function addYieldRate(uint32 groupId, uint256 effectiveDay, uint256 rateValue) external;

    function updateYieldRate(uint32 groupId, uint256 effectiveDay, uint256 rateValue, uint256 recordIndex) external;
}

interface IYieldStreamerConfiguration is
    IYieldStreamerConfiguration_Errors,
    IYieldStreamerConfiguration_Events,
    IYieldStreamerConfiguration_Functions
{}
