// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { YieldStreamer } from "../YieldStreamer.sol";

/**
 * @title YieldStreamerHarness contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev A test harness contract that extends YieldStreamer for testing purposes.
 * Implements additional functions to manipulate and inspect internal state during testing.
 * This contract should not be used in production environments.
 */
contract YieldStreamerHarness is YieldStreamer {
    // -------------------- Libraries ----------------------------- //

    using SafeCast for uint256;

    // -------------------- Types --------------------------------- //
    /**
     * @dev Structure representing the storage layout for the harness-specific data.
     *
     * Fields:
     * - `currentBlockTimestamp`: The simulated current block timestamp used when `usingSpecialBlockTimestamps` is true.
     * - `usingSpecialBlockTimestamps`: Flag indicating whether to use the simulated block timestamp or the real one.
     *
     * @custom:storage-location erc7201:cloudwalk.yieldstreamer.harness.storage
     */
    struct YieldStreamerHarnessLayout {
        uint40 currentBlockTimestamp;
        bool usingSpecialBlockTimestamps;
    }

    // ------------------ Constants ------------------------------- //

    /**
     * @dev Storage slot location for the harness contract's data.
     * Calculated as:
     * keccak256(abi.encode(uint256(keccak256(cloudwalk.yieldstreamer.harness.storage)) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 private constant _YIELD_STREAMER_HARNESS_STORAGE_LOCATION =
        0xa0e9aa00629651c83e3ff3c77329b09e5ba18a6c783982d308dc0dd0f2f6a800;

    /// @dev Role identifier for the harness administrator.
    bytes32 public constant HARNESS_ADMIN_ROLE = keccak256("HARNESS_ADMIN_ROLE");

    // ------------------ Functions ------------------------------- //

    /**
     * @dev Initializes the harness by setting up the harness admin role.
     * Can only be called by an account with the `OWNER_ROLE`.
     * Assigns the `OWNER_ROLE` as the admin of `HARNESS_ADMIN_ROLE`.
     */
    function initHarness() external onlyRole(OWNER_ROLE) {
        _setRoleAdmin(HARNESS_ADMIN_ROLE, OWNER_ROLE);
    }

    /**
     * @dev Deletes all yield rate records for a specific group.
     * Useful for resetting the state during testing.
     * Can only be called by an account with the `HARNESS_ADMIN_ROLE`.
     *
     * @param groupId The ID of the group whose yield rates will be deleted.
     */
    function deleteYieldRates(uint256 groupId) external onlyRole(HARNESS_ADMIN_ROLE) {
        delete _yieldStreamerStorage().yieldRates[uint32(groupId)];
    }

    /**
     * @dev Sets the yield state for a specific account.
     * Allows direct manipulation of the yield state during testing.
     * Can only be called by an account with the `HARNESS_ADMIN_ROLE`.
     *
     * @param account The address of the account whose yield state will be set.
     * @param newState The new `YieldState` to assign to the account.
     */
    function setYieldState(address account, YieldState calldata newState) external onlyRole(HARNESS_ADMIN_ROLE) {
        _yieldStreamerStorage().yieldStates[account] = newState;
    }

    /**
     * @dev Resets the yield state of a specific account to default values.
     * Effectively deletes the yield state record for the account.
     * Can only be called by an account with the `HARNESS_ADMIN_ROLE`.
     *
     * @param account The address of the account whose yield state will be reset.
     */
    function resetYieldState(address account) external onlyRole(HARNESS_ADMIN_ROLE) {
        delete _yieldStreamerStorage().yieldStates[account];
    }

    /**
     * @dev Sets a custom block timestamp to be used by the contract in certain conditions.
     * When `usingSpecialBlockTimestamps` is true, this timestamp will be used instead of the real block timestamp.
     * Can only be called by an account with the `HARNESS_ADMIN_ROLE`.
     *
     * @param day The day index since the Unix epoch (number of days since Jan 1, 1970).
     * @param time The number of seconds since the beginning of the specified day.
     */
    function setBlockTimestamp(uint256 day, uint256 time) external onlyRole(HARNESS_ADMIN_ROLE) {
        YieldStreamerHarnessLayout storage harnessStorage = _yieldStreamerHarnessStorage();
        harnessStorage.currentBlockTimestamp = (day * (24 * 60 * 60) + time).toUint40();
    }

    /**
     * @dev Enables or disables the use of the custom block timestamp.
     * When enabled (`true`), the contract will use the timestamp set via `setBlockTimestamp`.
     * When disabled (`false`), the contract will use the real block timestamp.
     * Can only be called by an account with the `HARNESS_ADMIN_ROLE`.
     *
     * @param newValue If `true`, use the custom block timestamp; if `false`, use the real block timestamp.
     */
    function setUsingSpecialBlockTimestamps(bool newValue) external onlyRole(HARNESS_ADMIN_ROLE) {
        YieldStreamerHarnessLayout storage harnessStorage = _yieldStreamerHarnessStorage();
        harnessStorage.usingSpecialBlockTimestamps = newValue;
    }

    // ------------------ View functions -------------------------- //

    /**
     * @dev Retrieves the current harness storage layout.
     * Provides access to the harness-specific internal state for testing purposes.
     *
     * @return A `YieldStreamerHarnessLayout` struct containing the current harness storage state.
     */
    function getHarnessStorageLayout() external view returns (YieldStreamerHarnessLayout memory) {
        return _yieldStreamerHarnessStorage();
    }

    // ------------------ Overrides ------------------------------- //

    /**
     * @dev Overrides the `_blockTimestamp` function to return either the custom timestamp or the real one.
     * If `usingSpecialBlockTimestamps` is `true`, returns the custom timestamp adjusted by `NEGATIVE_TIME_SHIFT`.
     * If `usingSpecialBlockTimestamps` is `false`, calls the parent `_blockTimestamp` implementation.
     *
     * @return The current block timestamp used by the contract (adjusted for testing if applicable).
     */
    function _blockTimestamp() internal view override returns (uint256) {
        YieldStreamerHarnessLayout storage harnessStorage = _yieldStreamerHarnessStorage();
        if (harnessStorage.usingSpecialBlockTimestamps) {
            uint256 blockTimestamp_ = harnessStorage.currentBlockTimestamp;
            if (blockTimestamp_ < NEGATIVE_TIME_SHIFT) {
                return 0;
            } else {
                return blockTimestamp_ - NEGATIVE_TIME_SHIFT;
            }
        } else {
            return super._blockTimestamp();
        }
    }

    // ------------------ Internal functions ---------------------- //

    /**
     * @dev Accessor for the harness contract's namespaced storage.
     * Retrieves a reference to the `YieldStreamerHarnessLayout` storage struct.
     * Uses a fixed storage slot to avoid conflicts with other contracts.
     *
     * @return $ A storage pointer to the `YieldStreamerHarnessLayout` struct.
     */
    function _yieldStreamerHarnessStorage() internal pure returns (YieldStreamerHarnessLayout storage $) {
        assembly {
            $.slot := _YIELD_STREAMER_HARNESS_STORAGE_LOCATION
        }
    }
}
