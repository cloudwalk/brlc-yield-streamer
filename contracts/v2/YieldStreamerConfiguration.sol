// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { IYieldStreamerConfiguration } from "./interfaces/IYieldStreamerConfiguration.sol";
import { YieldStreamerStorage } from "./YieldStreamerStorage.sol";

contract YieldStreamerConfiguration is YieldStreamerStorage, IYieldStreamerConfiguration {
    function assignGroup(bytes32 groupId, address[] memory accounts) external {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();

        for (uint256 i = 0; i < accounts.length; i++) {
            if ($.groups[accounts[i]] == groupId) {
                revert YieldStreamer_GroupAlreadyAssigned(accounts[i]);
            }

            $.groups[accounts[i]] = groupId;

            emit YieldStreamer_GroupAssigned(groupId, accounts[i]);
        }
    }

    function addYieldRate(bytes32 groupId, uint256 effectiveDay, uint256 rateValue) external {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldRate[] storage yieldRates = $.yieldRates[groupId];

        if (yieldRates.length > 0 && yieldRates[yieldRates.length - 1].effectiveDay >= effectiveDay) {
            revert YieldStreamer_YieldRateInvalidEffectiveDay();
        }
        if (yieldRates.length > 0 && yieldRates[yieldRates.length - 1].value == rateValue) {
            revert YieldStreamer_YieldRateValueAlreadyConfigured();
        }

        $.yieldRates[groupId].push(YieldRate({ effectiveDay: effectiveDay, value: rateValue }));

        emit YieldStreamer_YieldRateAdded(groupId, effectiveDay, rateValue);
    }

    function updateYieldRate(bytes32 groupId, uint256 effectiveDay, uint256 rateValue, uint256 recordIndex) external {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldRate[] storage yieldRates = $.yieldRates[groupId];

        if (recordIndex >= yieldRates.length) {
            revert YieldStreamer_YieldRateWrongIndex();
        }

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
}
