// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { Bitwise } from "./libs/Bitwise.sol";
import { YieldStreamerStorage } from "./YieldStreamerStorage.sol";
import { IYieldStreamerInitialization_Errors } from "./interfaces/IYieldStreamerInitialization.sol";
import { IYieldStreamerInitialization_Events } from "./interfaces/IYieldStreamerInitialization.sol";
import { IYieldStreamerV1 } from "./interfaces/IYieldStreamerV1.sol";

/**
 * @title YieldStreamerInitialization contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev The contract that responsible for yield state initialization.
 */
abstract contract YieldStreamerInitialization is
    YieldStreamerStorage,
    IYieldStreamerInitialization_Errors,
    IYieldStreamerInitialization_Events
{
    // ------------------ Libs ------------------------------------ //

    using SafeCast for uint256;
    using Bitwise for uint8;

    // ------------------ Functions --------------------------------- //

    /**
     * @dev Initializes multiple accounts in a hard mode (reverts if any account is already initialized).
     * @param accounts The accounts to initialize.
     */
    function _initializeMultipleAccounts(address[] calldata accounts) internal {
        if (accounts.length == 0) {
            revert YieldStreamer_EmptyArray();
        }

        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldStreamerInitializationStorageLayout storage $init = _yieldStreamerInitializationStorage();
        IYieldStreamerV1 sourceYieldStreamer = IYieldStreamerV1($init.sourceYieldStreamer);
        uint256 blockTimestamp = _blockTimestamp();

        _validateSourceYieldStreamer(sourceYieldStreamer);

        uint256 len = accounts.length;
        for (uint256 i = 0; i < len; ++i) {
            address account = accounts[i];
            YieldState storage state = $.yieldStates[account];

            if (state.flags.isBitSet(uint256(YieldStateFlagIndex.Initialized))) {
                revert YieldStreamer_AccountAlreadyInitialized(account);
            }
            if (account == address(0)) {
                revert YieldStreamer_AccountInitializationProhibited(account);
            }

            bytes32 groupKey = sourceYieldStreamer.getAccountGroup(account);

            _initializeAccount(
                account,
                $init.groupIds[groupKey],
                blockTimestamp,
                $.underlyingToken,
                sourceYieldStreamer,
                state
            );
        }
    }

    /**
     * @dev Initializes a single account in a soft mode (does nothing if the account is already initialized).
     * @param account The account to initialize.
     */
    function _initializeSingleAccount(address account) internal virtual {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldState storage state = $.yieldStates[account];

        if (state.flags.isBitSet(uint256(YieldStateFlagIndex.Initialized))) {
            return;
        }

        YieldStreamerInitializationStorageLayout storage $init = _yieldStreamerInitializationStorage();
        IYieldStreamerV1 sourceYieldStreamer = IYieldStreamerV1($init.sourceYieldStreamer);

        _validateSourceYieldStreamer(sourceYieldStreamer);

        bytes32 groupKey = sourceYieldStreamer.getAccountGroup(account);

        _initializeAccount(
            account,
            $init.groupIds[groupKey],
            _blockTimestamp(),
            $.underlyingToken,
            sourceYieldStreamer,
            state
        );
    }

    /**
     * @dev Initializes a given account.
     * @param account The account to initialize.
     * @param groupId The group id to assign the account to.
     * @param timestamp The timestamp at the time of initialization.
     * @param underlyingToken The underlying token address.
     * @param sourceYieldStreamer The source yield streamer address.
     * @param state The yield state to initialize.
     */
    function _initializeAccount(
        address account,
        uint256 groupId,
        uint256 timestamp,
        address underlyingToken,
        IYieldStreamerV1 sourceYieldStreamer,
        YieldState storage state
    ) internal virtual {
        _assignSingleAccountToGroup(groupId, account);

        IYieldStreamerV1.ClaimResult memory claimPreview = sourceYieldStreamer.claimAllPreview(account);
        sourceYieldStreamer.blocklist(account);

        state.accruedYield = (claimPreview.primaryYield + claimPreview.lastDayPartialYield).toUint64();
        state.lastUpdateBalance = IERC20(underlyingToken).balanceOf(account).toUint64();
        state.lastUpdateTimestamp = timestamp.toUint40();
        state.flags = state.flags.setBit(uint256(YieldStateFlagIndex.Initialized));

        emit YieldStreamer_AccountInitialized(
            account,
            groupId,
            state.lastUpdateBalance,
            state.accruedYield,
            state.streamYield
        );
    }

    /**
     * @dev Sets the initialized flag for an account.
     * @param account The account to set the initialized flag for.
     * @param isInitialized The initialized flag to set.
     */
    function _setInitializedFlag(address account, bool isInitialized) internal {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldState storage state = $.yieldStates[account];

        if (isInitialized && !state.flags.isBitSet(uint256(YieldStateFlagIndex.Initialized))) {
            state.flags = state.flags.setBit(uint256(YieldStateFlagIndex.Initialized));
            emit YieldStreamer_InitializedFlagSet(account, true);
        } else if (!isInitialized && state.flags.isBitSet(uint256(YieldStateFlagIndex.Initialized))) {
            state.flags = state.flags.clearBit(uint256(YieldStateFlagIndex.Initialized));
            emit YieldStreamer_InitializedFlagSet(account, false);
        }
    }

    /**
     * @dev Sets the source yield streamer.
     * @param newSourceYieldStreamer The new source yield streamer.
     */
    function _setSourceYieldStreamer(address newSourceYieldStreamer) internal {
        YieldStreamerInitializationStorageLayout storage $init = _yieldStreamerInitializationStorage();

        if ($init.sourceYieldStreamer == newSourceYieldStreamer) {
            revert YieldStreamer_SourceYieldStreamerAlreadyConfigured();
        }

        emit YieldStreamer_SourceYieldStreamerChanged($init.sourceYieldStreamer, newSourceYieldStreamer);

        $init.sourceYieldStreamer = newSourceYieldStreamer;
    }

    /**
     * @dev Sets the group mapping for the source yield streamer.
     * @param groupKey The group key to map from.
     * @param groupId The group id to map to.
     */
    function _mapSourceYieldStreamerGroup(bytes32 groupKey, uint256 groupId) internal {
        YieldStreamerInitializationStorageLayout storage $init = _yieldStreamerInitializationStorage();
        uint256 oldGroupId = $init.groupIds[groupKey];

        if (oldGroupId == groupId) {
            revert YieldStreamer_SourceYieldStreamerGroupAlreadyMapped();
        }

        $init.groupIds[groupKey] = groupId;

        emit YieldStreamer_GroupMapped(groupKey, groupId, oldGroupId);
    }

    /**
     * @dev Validates the source yield streamer.
     * @param sourceYieldStreamer The source yield streamer to validate.
     */
    function _validateSourceYieldStreamer(IYieldStreamerV1 sourceYieldStreamer) private view {
        if (address(sourceYieldStreamer) == address(0)) {
            revert YieldStreamer_SourceYieldStreamerNotConfigured();
        }
        if (!sourceYieldStreamer.isBlocklister(address(this))) {
            revert YieldStreamer_SourceYieldStreamerUnauthorizedBlocklister();
        }
    }

    // ------------------ Overrides ------------------------------- //

    /**
     * @dev Returns the current block timestamp.
     */
    function _blockTimestamp() internal view virtual returns (uint256);

    /**
     * @dev Assigns an account to a group.
     * @param groupId The group id to assign the account to.
     * @param account The account to assign to the group.
     */
    function _assignSingleAccountToGroup(uint256 groupId, address account) internal virtual;
}
