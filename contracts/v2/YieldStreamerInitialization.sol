// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { YieldStreamerConfiguration } from "./YieldStreamerConfiguration.sol";
import { YieldStreamerPrimary } from "./YieldStreamerPrimary.sol";
import { YieldStreamerStorage } from "./YieldStreamerStorage.sol";
import { Utils } from "./libs/Utils.sol";

import { IYieldStreamerInitialization_Errors } from "./interfaces/IYieldStreamerInitialization.sol";
import { IYieldStreamerInitialization_Events } from "./interfaces/IYieldStreamerInitialization.sol";
import { IYieldStreamerInitialization_Types } from "./interfaces/IYieldStreamerInitialization.sol";
import { IYieldStreamerV1 } from "./interfaces/IYieldStreamerV1.sol";

abstract contract YieldStreamerInitialization is
    YieldStreamerStorage,
    YieldStreamerPrimary,
    YieldStreamerConfiguration,
    IYieldStreamerInitialization_Types,
    IYieldStreamerInitialization_Errors,
    IYieldStreamerInitialization_Events
{
    // -------------------- Libraries -------------------- //

    using SafeCast for uint256;

    // ------------------ Functions ------------------ //
    function _initializeAccountBatch(
        uint256 groupId,
        uint256 mode,
        uint256 startYieldOrParameter,
        address[] calldata accounts
    ) internal virtual {
        YieldStreamerStorageLayout storage primaryStorage = _yieldStreamerStorage();

        // TODO: Move sourceYieldStreamer to the primary storage

        address sourceYieldStreamer = _yieldStreamerInitializationStorage().sourceYieldStreamer;
        _validateInitialization(groupId, mode, sourceYieldStreamer);

        uint256 accountCount = accounts.length;
        for (uint256 i = 0; i < accountCount; ++i) {
            _initializeAccount(
                groupId, // Tools: this comment prevents Prettier from formatting into a single line.
                mode,
                accounts[i],
                startYieldOrParameter,
                sourceYieldStreamer,
                primaryStorage
            );
        }
    }

    function _initializeAccount(
        uint256 groupId,
        uint256 mode,
        address account,
        uint256 startYieldOrParameter,
        address sourceYieldStreamer,
        YieldStreamerStorageLayout storage primaryStorage
    ) internal virtual {
        YieldState storage yieldState = primaryStorage.yieldStates[account];

        if (Utils._isBitSet(yieldState.flags, uint256(YieldStateFlagIndex.Initialized))) {
            revert YieldStreamer_AccountAlreadyInitialized(account);
        }
        if (account == address(0)) {
            revert YieldStreamer_AccountInitializationProhibited(account);
        }

        _assignAccountToGroup(uint32(groupId), account, primaryStorage);

        if (mode == uint256(InitializationMode.Migration)) {
            _migrateState(account, sourceYieldStreamer, yieldState);
            _blockAccountOnSourceYieldStreamer(account, sourceYieldStreamer);
        } else {
            yieldState.accruedYield = startYieldOrParameter.toUint64();
            yieldState.balanceAtLastUpdate = IERC20(primaryStorage.underlyingToken).balanceOf(account).toUint64();
            yieldState.timestampAtLastUpdate = _blockTimestamp().toUint40();
        }
    }

    function _setSourceYieldStreamer(address sourceYieldStreamer) internal {
        YieldStreamerInitializationStorageLayout storage $ = _yieldStreamerInitializationStorage();

        if ($.sourceYieldStreamer == sourceYieldStreamer) {
            return;
        }

        emit YieldStreamer_SourceYieldStreamerChanged(sourceYieldStreamer, $.sourceYieldStreamer);

        $.sourceYieldStreamer = sourceYieldStreamer;
    }

    function _validateInitialization(
        uint256 groupId, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 mode,
        address sourceYieldStreamer
    ) internal pure {
        if (groupId == 0 || groupId > type(uint32).max) {
            revert YieldStreamer_GroupForInitializationInvalid();
        }
        if (mode == uint256(InitializationMode.Migration)) {
            if (sourceYieldStreamer == address(0)) {
                revert YieldStreamer_SourceYieldStreamerNotConfigured();
            }
            // TODO: Check we can block users on the source yield streamer
        }
    }

    function _migrateState(
        address account, // Tools: this comment prevents Prettier from formatting into a single line.
        address sourceYieldStreamer,
        YieldState storage state
    ) internal {
        IYieldStreamerV1.ClaimResult memory claimPreview = IYieldStreamerV1(sourceYieldStreamer).claimAllPreview(
            account
        );
        state.accruedYield = (claimPreview.primaryYield + claimPreview.lastDayYield).toUint64();
        // TODO: Make other migration things
    }

    function _blockAccountOnSourceYieldStreamer(
        address account, // Tools: this comment prevents Prettier from formatting into a single line.
        address sourceYieldStreamer
    ) internal pure {
        account;
        sourceYieldStreamer;
        //TODO: Implement
    }
}
