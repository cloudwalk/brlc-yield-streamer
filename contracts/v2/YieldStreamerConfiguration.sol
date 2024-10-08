// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IYieldStreamerConfiguration } from "./interfaces/IYieldStreamerConfiguration.sol";
import { YieldStreamerStorage } from "./YieldStreamerStorage.sol";

abstract contract YieldStreamerConfiguration is YieldStreamerStorage, IYieldStreamerConfiguration {
    function assignGroup(uint32 groupId, address[] memory accounts, bool accrueYield) external {
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

    function addYieldRate(uint32 groupId, uint256 effectiveDay, uint256 rateValue) external {
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

    function updateYieldRate(uint32 groupId, uint256 effectiveDay, uint256 rateValue, uint256 recordIndex) external {
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

    function _accrueYield(
        address account,
        YieldState storage state,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) internal virtual;

    function _blockTimestamp() internal view virtual returns (uint256);
}
