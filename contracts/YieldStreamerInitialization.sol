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
 * @dev The contract that responsible for the yield streamer initialization.
 */
abstract contract YieldStreamerInitialization is
    YieldStreamerStorage,
    IYieldStreamerInitialization_Errors,
    IYieldStreamerInitialization_Events
{
    // ------------------ Libraries ------------------------------- //

    using SafeCast for uint256;
    using Bitwise for uint8;

    // ------------------ Functions ------------------------------- //

    /**
     * @dev Initializes multiple accounts by setting up their yield states.
     *
     * @param accounts The array of account addresses to initialize.
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
     * @dev Initializes a single account by setting up its yield state.
     * If the account is already initialized, the function returns immediately without any action.
     *
     * @param account The account address to initialize.
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
     * @dev Internal function to initialize the yield state for a given account.
     *
     * @param account The account address to initialize.
     * @param groupId The group ID to assign the account to.
     * @param timestamp The current block timestamp at the time of initialization.
     * @param underlyingToken The address of the underlying token contract.
     * @param sourceYieldStreamer The instance of the source yield streamer contract.
     * @param state The yield state storage reference for the account.
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
     * @dev Manually sets the initialized flag for an account's yield state.
     *
     * @param account The account address to update.
     * @param isInitialized The boolean value to set for the initialized flag.
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
     * @dev Sets the address of the source yield streamer contract.
     * The source yield streamer is used to initialize account yield states based on existing data.
     *
     * @param newSourceYieldStreamer The address of the new source yield streamer contract.
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
     * @dev Maps a group key from the source yield streamer to a group ID in this contract.
     *
     * @param groupKey The group key identifier from the source yield streamer.
     * @param groupId The group ID in this yield streamer to map to.
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
     * @dev Validates that the source yield streamer is properly configured and that this contract
     * is authorized as a blocklister in the source yield streamer contract.
     *
     * @param sourceYieldStreamer The instance of the source yield streamer contract to validate.
     */
    function _validateSourceYieldStreamer(IYieldStreamerV1 sourceYieldStreamer) private view {
        if (address(sourceYieldStreamer) == address(0)) {
            revert YieldStreamer_SourceYieldStreamerNotConfigured();
        }
        if (!sourceYieldStreamer.isBlocklister(address(this))) {
            revert YieldStreamer_SourceYieldStreamerUnauthorizedBlocklister();
        }
    }

    /**
     * @dev Retrieves the address of the configured source yield streamer contract.
     *
     * @return The address of the source yield streamer contract.
     */
    function _sourceYieldStreamer() internal view returns (address) {
        return _yieldStreamerInitializationStorage().sourceYieldStreamer;
    }

    // ------------------ Overrides ------------------------------- //

    /**
     * @dev Returns the current block timestamp, possibly adjusted or overridden by inheriting contracts.
     * Should be overridden by inheriting contracts to provide the correct block timestamp.
     *
     * @return The current block timestamp as a uint256.
     */
    function _blockTimestamp() internal view virtual returns (uint256);

    /**
     * @dev Assigns an account to a specified group ID.
     * Should be implemented by inheriting contracts to define how accounts are assigned to groups.
     *
     * @param groupId The group ID to assign the account to.
     * @param account The account address to assign to the group.
     */
    function _assignSingleAccountToGroup(uint256 groupId, address account) internal virtual;
}
