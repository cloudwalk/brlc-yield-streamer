// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { YieldStreamerStorage } from "./YieldStreamerStorage.sol";
import { IYieldStreamerInitialization_Types } from "./interfaces/IYieldStreamerInitialization.sol";
import { IYieldStreamerInitialization_Events } from "./interfaces/IYieldStreamerInitialization.sol";
import { IYieldStreamerV1 } from "./interfaces/IYieldStreamerV1.sol";

abstract contract YieldStreamerInitialization is
    YieldStreamerStorage,
    IYieldStreamerInitialization_Types,
    IYieldStreamerInitialization_Events
{
    // ------------------ Functions ------------------ //

    function _initializeYieldState(address account) internal virtual {
        YieldStreamerInitializationStorageLayout storage $ = _yieldStreamerInitializationStorage();

        if ($.sourceYieldStreamer == address(0)) {
            return;
        }

        // TODO: See how much gas left and if it's over cap don't call claimAllPreview?

        try IYieldStreamerV1($.sourceYieldStreamer).claimAllPreview(account) returns (
            IYieldStreamerV1.ClaimResult memory claimResult
        ) {
            _initializeYieldState(account, claimResult);
        } catch Error(string memory reason) {
            emit YieldStreamer_YieldStateInitializationFailed(account, reason, 0, "");
        } catch Panic(uint errorCode) {
            emit YieldStreamer_YieldStateInitializationFailed(account, "", errorCode, "");
        } catch (bytes memory lowLevelData) {
            emit YieldStreamer_YieldStateInitializationFailed(account, "", 0, lowLevelData);
        }
    }

    function _initializeYieldState(address account, uint256 yield) internal {
    }

    function _initializeYieldState(address account, IYieldStreamerV1.ClaimResult memory claimResult) internal {
        // TBD
    }

    function _initializeYieldState(IYieldStreamerV1.ClaimResult memory claimResult) internal {
        // TBD
    }

    function _setSourceYieldStreamer(address sourceYieldStreamer) internal {
        YieldStreamerInitializationStorageLayout storage $ = _yieldStreamerInitializationStorage();

        if ($.sourceYieldStreamer == sourceYieldStreamer) {
            return;
        }

        emit YieldStreamer_SourceYieldStreamerChanged(sourceYieldStreamer, $.sourceYieldStreamer);

        $.sourceYieldStreamer = sourceYieldStreamer;
    }
}
