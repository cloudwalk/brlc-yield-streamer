// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { YieldStreamerStorage } from "./YieldStreamerStorage.sol";
import { IYieldStreamerInitialization_Types } from "./interfaces/IYieldStreamerInitialization.sol";
import { IYieldStreamerInitialization_Errors } from "./interfaces/IYieldStreamerInitialization.sol";
import { IYieldStreamerInitialization_Events } from "./interfaces/IYieldStreamerInitialization.sol";
import { IYieldStreamerV1 } from "./interfaces/IYieldStreamerV1.sol";

/**
 * @title YieldStreamerInitialization contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev The contract that responsible for initializing the yield state.
 */
abstract contract YieldStreamerInitialization is
    YieldStreamerStorage,
    IYieldStreamerInitialization_Types,
    IYieldStreamerInitialization_Errors,
    IYieldStreamerInitialization_Events
{
    // ------------------ Functions ------------------------------- //

    /**
     * @dev Initializes the yield state for a given accounts.
     * @param accounts The accounts to initialize the yield state for.
     */
    function _initializeYieldState(address[] memory accounts) internal {
        if (accounts.length == 0) {
            revert YieldStreamer_EmptyArray();
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            _initializeYieldState(accounts[i]);
        }
    }

    /**
     * @dev Initializes the yield state for a given accounts and yields.
     * @param accounts The accounts to initialize the yield state for.
     * @param yields The yields to initialize the yield state for.
     */
    function _initializeYieldState(address[] memory accounts, uint256[] memory yields) internal {
        if (accounts.length == 0) {
            revert YieldStreamer_EmptyArray();
        }
        if (accounts.length != yields.length) {
            revert YieldStreamer_InvalidArrayLength();
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            _initializeYieldState(accounts[i], yields[i]);
        }
    }

    /**
     * @dev Initializes the yield state for a given account.
     * @param account The account to initialize the yield state for.
     */
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

    /**
     * @dev Initializes the yield state for a given account and yield.
     * @param account The account to initialize the yield state for.
     * @param yield The yield to initialize the yield state for.
     */
    function _initializeYieldState(address account, uint256 yield) internal {
        // TBD
    }

    /**
     * @dev Initializes the yield state for a given account and claim result.
     * @param account The account to initialize the yield state for.
     * @param claimResult The claim result to initialize the yield state from.
     */
    function _initializeYieldState(address account, IYieldStreamerV1.ClaimResult memory claimResult) internal {
        // TBD
    }

    /**
     * @dev Sets the source yield streamer.
     * @param newSourceYieldStreamer The new source yield streamer.
     */
    function _setSourceYieldStreamer(address newSourceYieldStreamer) internal {
        YieldStreamerInitializationStorageLayout storage $ = _yieldStreamerInitializationStorage();

        if ($.sourceYieldStreamer == newSourceYieldStreamer) {
            return;
        }

        emit YieldStreamer_SourceYieldStreamerChanged($.sourceYieldStreamer, newSourceYieldStreamer);

        $.sourceYieldStreamer = newSourceYieldStreamer;
    }
}
