// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

interface IYieldStreamerConfiguration {
    // -------------------- Errors -------------------- //

    error YieldStreamer_YieldRateWrongIndex();

    error YieldStreamer_YieldRateInvalidEffectiveDay();

    error YieldStreamer_YieldRateValueAlreadyConfigured();

    error YieldStreamer_GroupAlreadyAssigned(address account);

    // -------------------- Events -------------------- //

    event YieldStreamer_GroupAssigned(bytes32 indexed groupId, address indexed account);

    event YieldStreamer_YieldRateAdded(bytes32 indexed groupId, uint256 effectiveDay, uint256 rateValue);

    event YieldStreamer_YieldRateUpdated(bytes32 indexed groupId, uint256 effectiveDay, uint256 rateValue, uint256 index);

    // -------------------- Functions -------------------- //

    function assignGroup(bytes32 groupId, address[] memory accounts, bool accrueYield) external;

    function addYieldRate(bytes32 groupId, uint256 effectiveDay, uint256 rateValue) external;

    function updateYieldRate(bytes32 groupId, uint256 effectiveDay, uint256 rateValue, uint256 recordIndex) external;
}
