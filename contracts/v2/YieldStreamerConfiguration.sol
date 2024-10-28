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
    // ------------------ Libraries ------------------------------- //

    using SafeCast for uint256;

    // ------------------ Functions ------------------------------- //

    /**
    //  * @dev Adds a new yield rate entry for a specific group.
    //  * The yield rate becomes effective starting from the specified effective day.
    //  * The `effectiveDay` represents the day index since the Unix epoch (i.e., number of days since timestamp zero).
    //  *
    //  * @param groupId The ID of the group to add the yield rate to.
    //  * @param effectiveDay The day number from which the yield rate becomes effective for the group.
    //  * @param tierRates The yield rate value for each tier (scaled by RATE_FACTOR).
    //  * @param tierCaps The balance cap for each tier.
    //  */
    function _addYieldRate(
        uint256 groupId, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 effectiveDay,
        uint256[] memory tierRates,
        uint256[] memory tierCaps
    ) internal {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldTieredRate[] storage rates = $.yieldRates[groupId.toUint32()];

        // Ensure first item in the array always starts with effectiveDay 0
        if (rates.length == 0 && effectiveDay != 0) {
            revert YieldStreamer_YieldRateInvalidEffectiveDay();
        }

        // Ensure that rates are always in ascending order
        if (rates.length > 0 && rates[rates.length - 1].effectiveDay >= effectiveDay) {
            revert YieldStreamer_YieldRateInvalidEffectiveDay();
        }

        // Initialize a new `YieldTieredRate` struct in storage
        rates.push();
        YieldTieredRate storage newYieldRate = rates[rates.length - 1];

        // Set the effective day of the new yield tiered rate
        newYieldRate.effectiveDay = effectiveDay.toUint16();

        // Add the tiers to the new yield tiered rate
        for (uint256 i = 0; i < tierRates.length; i++) {
            newYieldRate.tiers.push(YieldRateTier({ rate: tierRates[i].toUint48(), cap: tierCaps[i].toUint64() }));
        }

        emit YieldStreamer_YieldTieredRateAdded(groupId, effectiveDay, tierRates, tierCaps);
    }

    /**
     * @dev Updates an existing yield rate entry for a specific group.
     * Allows modifying the `effectiveDay` and `rateValue` of a yield rate at a given index.
     *
     * @param groupId The ID of the group whose yield rate is being updated.
     * @param itemIndex The index of the yield rate in the group's rates array to update.
     * @param effectiveDay The new effective day for the yield rate.
     * @param tierRates The new yield rate value for each tier (scaled by RATE_FACTOR).
     * @param tierCaps The new balance cap for each tier.
     */
    function _updateYieldRate(
        uint256 groupId, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 itemIndex,
        uint256 effectiveDay,
        uint256[] memory tierRates,
        uint256[] memory tierCaps
    ) internal {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldTieredRate[] storage rates = $.yieldRates[groupId.toUint32()];

        // Ensure first item in the array always starts with effectiveDay = 0
        if (itemIndex == 0 && effectiveDay != 0) {
            revert YieldStreamer_YieldRateInvalidEffectiveDay();
        }

        // Ensure that item index is within the bounds of the array
        if (itemIndex >= rates.length) {
            revert YieldStreamer_YieldRateInvalidItemIndex();
        }

        // Ensure that rates are always in ascending order
        uint256 lastIndex = rates.length - 1;
        if (lastIndex != 0) {
            int256 intEffectiveDay = int256(effectiveDay);
            int256 previousEffectiveDay = itemIndex != 0
                ? int256(uint256(rates[itemIndex - 1].effectiveDay))
                : type(int256).min;
            int256 nextEffectiveDay = itemIndex != lastIndex
                ? int256(uint256(rates[itemIndex + 1].effectiveDay))
                : type(int256).max;
            if (intEffectiveDay <= previousEffectiveDay || intEffectiveDay >= nextEffectiveDay) {
                revert YieldStreamer_YieldRateInvalidEffectiveDay();
            }
        }

        YieldTieredRate storage rate = rates[itemIndex];

        // Update the effective day of the yield tiered rate
        rate.effectiveDay = effectiveDay.toUint16();

        // Update the tiers of the yield tiered rate
        delete rate.tiers;
        for (uint256 i = 0; i < tierRates.length; i++) {
            rate.tiers.push(YieldRateTier({ rate: tierRates[i].toUint48(), cap: tierCaps[i].toUint64() }));
        }

        emit YieldStreamer_YieldTieredRateUpdated(groupId, itemIndex, effectiveDay, tierRates, tierCaps);
    }

    /**
     * @dev Assigns multiple accounts to a group.
     * Attempts to assign each account to the specified group and accrues yield if specified.
     *
     * @param groupId The ID of the group to assign the accounts to.
     * @param accounts The array of account addresses to assign to the group.
     * @param forceYieldAccrue If true, accrues yield for the accounts before assignment.
     */
    function _assignMultipleAccountsToGroup(
        uint256 groupId, // Tools: this comment prevents Prettier from formatting into a single line.
        address[] memory accounts,
        bool forceYieldAccrue
    ) internal {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        uint32 localGroupId = groupId.toUint32();

        for (uint256 i = 0; i < accounts.length; i++) {
            Group storage group = $.groups[accounts[i]];

            if (group.id == localGroupId) {
                revert YieldStreamer_GroupAlreadyAssigned(accounts[i]);
            }

            if (forceYieldAccrue) {
                _accrueYield(accounts[i]);
            }

            emit YieldStreamer_GroupAssigned(accounts[i], localGroupId, group.id);

            group.id = localGroupId;
        }
    }

    /**
     * @dev Assigns a single account to a group in soft mode.
     * Assigns the account to the specified group if it is not already assigned.
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
     * @dev Sets the fee receiver address for the yield streamer.
     * The fee receiver is the address that will receive any fees deducted during yield claims.
     *
     * @param newFeeReceiver The new fee receiver address.
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
     * @dev Accrues yield for the specified account.
     * Should be overridden by inheriting contracts to implement the actual accrue logic.
     *
     * @param account The account to accrue yield for.
     */
    function _accrueYield(address account) internal virtual;

    /**
     * @dev Returns the current block timestamp.
     * Should be overridden by inheriting contracts if custom timekeeping is needed.
     *
     * @return The current block timestamp (Unix timestamp).
     */
    function _blockTimestamp() internal view virtual returns (uint256);
}
