// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { YieldStreamerStorage } from "./YieldStreamerStorage.sol";
import { IYieldStreamerConfiguration_Errors } from "./interfaces/IYieldStreamerConfiguration.sol";
import { IYieldStreamerConfiguration_Events } from "./interfaces/IYieldStreamerConfiguration.sol";

/**
 * @title YieldStreamerConfiguration contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev The contract that responsible for the yield streamer configuration.
 */
abstract contract YieldStreamerConfiguration is
    YieldStreamerStorage,
    IYieldStreamerConfiguration_Errors,
    IYieldStreamerConfiguration_Events
{
    // ------------------ Libs ------------------------------------ //

    using SafeCast for uint256;

    // ------------------ Functions ------------------------------- //

    /**
     *  @dev Adds a new yield rate to the yield streamer.
     *
     * Emits:
     *  - {YieldStreamer_YieldRateAdded}
     *
     * @param groupId The ID of the group to add the yield rate to.
     * @param effectiveDay The effective day of the yield rate.
     * @param rateValue The value of the yield rate.
     */
    function _addYieldRate(
        uint32 groupId, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 effectiveDay,
        uint256 rateValue
    ) internal {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldRate[] storage yieldRates = $.yieldRates[groupId];

        // Ensure first item in the array always starts with effectiveDay 0
        if (yieldRates.length == 0 && effectiveDay != 0) {
            revert YieldStreamer_YieldRateInvalidEffectiveDay();
        }

        // Ensure that rates are always in ascending order
        if (yieldRates.length > 0 && yieldRates[yieldRates.length - 1].effectiveDay >= effectiveDay) {
            revert YieldStreamer_YieldRateInvalidEffectiveDay();
        }

        // Ensure that rates are not duplicated
        if (yieldRates.length > 0 && yieldRates[yieldRates.length - 1].value == rateValue) {
            revert YieldStreamer_YieldRateAlreadyConfigured();
        }

        yieldRates.push(YieldRate({ effectiveDay: effectiveDay.toUint16(), value: rateValue.toUint32() }));

        emit YieldStreamer_YieldRateAdded(groupId, effectiveDay, rateValue);
    }

    /**
     * @dev Updates a yield rate in the yield streamer.
     *
     * Emits:
     *  - {YieldStreamer_YieldRateUpdated}
     *
     * @param groupId The ID of the group to update the yield rate for.
     * @param itemIndex The index of the yield rate to update.
     * @param effectiveDay The effective day of the yield rate.
     * @param rateValue The value of the yield rate.
     */
    function _updateYieldRate(
        uint32 groupId, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 itemIndex,
        uint256 effectiveDay,
        uint256 rateValue
    ) internal {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldRate[] storage yieldRates = $.yieldRates[groupId];

        // Ensure first item in the array always starts with effectiveDay = 0
        if (itemIndex == 0 && effectiveDay != 0) {
            revert YieldStreamer_YieldRateInvalidEffectiveDay();
        }

        // Ensure that item index is within the bounds of the array
        if (itemIndex >= yieldRates.length) {
            revert YieldStreamer_YieldRateInvalidItemIndex();
        }

        // Ensure that rates are always in ascending order
        uint256 lastIndex = yieldRates.length - 1;
        if (lastIndex != 0) {
            int256 intEffectiveDay = int256(effectiveDay);
            int256 previousEffectiveDay = itemIndex != 0
                ? int256(uint256(yieldRates[itemIndex - 1].effectiveDay))
                : type(int256).min;
            int256 nextEffectiveDay = itemIndex != lastIndex
                ? int256(uint256(yieldRates[itemIndex + 1].effectiveDay))
                : type(int256).max;
            if (intEffectiveDay <= previousEffectiveDay || intEffectiveDay >= nextEffectiveDay) {
                revert YieldStreamer_YieldRateInvalidEffectiveDay();
            }
        }

        YieldRate storage yieldRate = yieldRates[itemIndex];

        emit YieldStreamer_YieldRateUpdated(groupId, itemIndex, effectiveDay, rateValue);

        yieldRate.effectiveDay = effectiveDay.toUint16();
        yieldRate.value = rateValue.toUint32();
    }

    /**
     * @dev Assigns multiple accounts to a group in a hard mode (reverts if any account is already
     *      assigned to the group).
     *
     * Emits:
     *  - {YieldStreamer_GroupAssigned}
     *
     * @param groupId The ID of the group to assign the accounts to.
     * @param accounts The accounts to assign to the group.
     * @param forceYieldAccrue Whether to accrue yield for the accounts.
     */
    function _assignMultipleAccountsToGroup(
        uint32 groupId, // Tools: this comment prevents Prettier from formatting into a single line.
        address[] memory accounts,
        bool forceYieldAccrue
    ) internal {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        uint256 toTimestamp = _blockTimestamp();

        for (uint256 i = 0; i < accounts.length; i++) {
            Group storage group = $.groups[accounts[i]];

            if (group.id == groupId) {
                revert YieldStreamer_GroupAlreadyAssigned(accounts[i]);
            }

            if (forceYieldAccrue) {
                YieldState storage state = $.yieldStates[accounts[i]];
                _accrueYield(accounts[i], state, state.timestampAtLastUpdate, toTimestamp);
            }

            emit YieldStreamer_GroupAssigned(accounts[i], groupId, group.id);

            group.id = groupId;
        }
    }

    /**
     * @dev Assigns a single account to a group in a soft mode (does nothing if the account is already
     *      assigned to the group).
     *
     * Emits:
     *  - {YieldStreamer_GroupAssigned}
     *
     * @param groupId The ID of the group to assign the account to.
     * @param account The account to assign to the group.
     */
    function _assignSingleAccountToGroup(uint256 groupId, address account) internal virtual {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        Group storage group = $.groups[account];

        if (group.id == groupId) {
            return;
        }

        emit YieldStreamer_GroupAssigned(account, groupId, group.id);

        $.groups[account].id = groupId.toUint32();
    }

    /**
     * @dev Sets the fee receiver for the yield streamer.
     *
     * Emits:
     *  - {YieldStreamer_FeeReceiverChanged}
     *
     * @param newFeeReceiver The new fee receiver.
     */
    function _setFeeReceiver(address newFeeReceiver) internal {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();

        if ($.feeReceiver == newFeeReceiver) {
            revert YieldStreamer_FeeReceiverAlreadyConfigured();
        }

        emit YieldStreamer_FeeReceiverChanged(newFeeReceiver, $.feeReceiver);

        $.feeReceiver = newFeeReceiver;
    }

    // ------------------ Overrides ------------------ //

    /**
     * @dev Accrues yield for the account.
     * @param account The account to accrue yield for.
     * @param state The current yield state of the account.
     * @param fromTimestamp The timestamp to accrue yield from.
     * @param toTimestamp The timestamp to accrue yield to.
     */
    function _accrueYield(
        address account,
        YieldState storage state,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) internal virtual;

    /**
     * @dev Returns the current block timestamp.
     */
    function _blockTimestamp() internal view virtual returns (uint256);
}
