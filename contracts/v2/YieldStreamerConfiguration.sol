// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { YieldStreamerStorage } from "./YieldStreamerStorage.sol";
import { AccessControlExtUpgradeable } from "./base/AccessControlExtUpgradeable.sol";
import { IYieldStreamerConfiguration_Errors } from "./interfaces/IYieldStreamerConfiguration.sol";
import { IYieldStreamerConfiguration_Events } from "./interfaces/IYieldStreamerConfiguration.sol";

abstract contract YieldStreamerConfiguration is
    YieldStreamerStorage,
    IYieldStreamerConfiguration_Errors,
    IYieldStreamerConfiguration_Events
{
    // ------------------ Functions ------------------ //

    function _assignGroup(
        uint32 groupId, // Tools: this comment prevents Prettier from formatting into a single line.
        address[] memory accounts,
        bool accrueYield
    ) internal {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        uint256 toTimestamp = _blockTimestamp();

        for (uint256 i = 0; i < accounts.length; i++) {
            Group storage group = $.groups[accounts[i]];

            if (group.id == groupId) {
                revert YieldStreamer_GroupAlreadyAssigned(accounts[i]);
            }

            if (accrueYield) {
                YieldState storage state = $.yieldStates[accounts[i]];
                _accrueYield(accounts[i], state, state.timestampAtLastUpdate, toTimestamp);
            }

            group.id = groupId;

            emit YieldStreamer_GroupAssigned(groupId, accounts[i]);
        }
    }

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

        // Ensure that rates are not duplicate
        if (yieldRates.length > 0 && yieldRates[yieldRates.length - 1].value == rateValue) {
            revert YieldStreamer_YieldRateValueAlreadyConfigured();
        }

        yieldRates.push(YieldRate({ effectiveDay: effectiveDay, value: rateValue }));

        emit YieldStreamer_YieldRateAdded(groupId, effectiveDay, rateValue);
    }

    function _updateYieldRate(
        uint32 groupId, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 effectiveDay,
        uint256 rateValue,
        uint256 recordIndex
    ) internal {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldRate[] storage yieldRates = $.yieldRates[groupId];

        // Ensure first item in the array always starts with effectiveDay 0
        if (recordIndex == 0 && effectiveDay != 0) {
            revert YieldStreamer_YieldRateInvalidEffectiveDay();
        }

        // Ensure that index is within the bounds of the array
        if (recordIndex >= yieldRates.length) {
            revert YieldStreamer_YieldRateWrongIndex();
        }

        // Ensure that rates are always in ascending order
        uint256 lastIndex = yieldRates.length - 1;
        if (lastIndex != 0) {
            int256 intEffectiveDay = int256(effectiveDay);
            int256 previousEffectiveDay = recordIndex != 0
                ? int256(uint256(yieldRates[recordIndex - 1].effectiveDay))
                : type(int256).min;
            int256 nextEffectiveDay = recordIndex != lastIndex
                ? int256(uint256(yieldRates[recordIndex + 1].effectiveDay))
                : type(int256).max;
            if (intEffectiveDay <= previousEffectiveDay || intEffectiveDay >= nextEffectiveDay) {
                revert YieldStreamer_YieldRateInvalidEffectiveDay();
            }
        }

        YieldRate storage yieldRate = yieldRates[recordIndex];

        emit YieldStreamer_YieldRateUpdated(groupId, effectiveDay, rateValue, recordIndex);

        yieldRate.effectiveDay = effectiveDay;
        yieldRate.value = rateValue;
    }

    function _setFeeReceiver(address newFeeReceiver) internal {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();

        if ($.feeReceiver == newFeeReceiver) {
            revert YieldStreamer_FeeReceiverAlreadyConfigured();
        }

        emit YieldStreamer_FeeReceiverChanged(newFeeReceiver, $.feeReceiver);

        $.feeReceiver = newFeeReceiver;
    }
    function _accrueYield(
        address account,
        YieldState storage state,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) internal virtual;

    function _blockTimestamp() internal view virtual returns (uint256);
}
