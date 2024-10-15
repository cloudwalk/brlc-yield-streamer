// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { YieldStreamerV2 } from "./YieldStreamerV2.sol";

/**
 * @title YieldStreamerV2Harness contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev A wrapper contract that implements additional functions for testing the YieldStreamerV2 contract.
 */
contract YieldStreamerV2Harness is YieldStreamerV2 {
    // -------------------- Libs ---------------------------------- //

    using SafeCast for uint256;

    // -------------------- Types --------------------------------- //
    /**
     * @dev The structure with the harness contract storage layout.
     * @custom:storage-location erc7201:cloudwalk.yieldstreamer.harness.storage
     */
    struct YieldStreamerHarnessLayout {
        uint40 currentBlockTimestamp;
        bool usingSpecialBlockTimestamps;
    }

    // ------------------ Constants ------------------------------- //

    /**
     * @dev The storage location of the yield streamer harness contract calculated as:
     *      keccak256(abi.encode(uint256(keccak256(nameId)) - 1)) & ~bytes32(uint256(0xff))
     *      where nameId = "cloudwalk.yieldstreamer.harness.storage".
     */
    bytes32 private constant _YIELD_STREAMER_HARNESS_STORAGE_LOCATION =
        0xa0e9aa00629651c83e3ff3c77329b09e5ba18a6c783982d308dc0dd0f2f6a800;

    /// @dev The role of this contract harness admin.
    bytes32 public constant HARNESS_ADMIN_ROLE = keccak256("HARNESS_ADMIN_ROLE");

    // ------------------ Functions ------------------------------- //

    /**
     * @dev Initiates the harness part of the yield streamer contract.
     */
    function initHarness() external onlyRole(OWNER_ROLE) {
        _setRoleAdmin(HARNESS_ADMIN_ROLE, OWNER_ROLE);
    }

    /**
     * @dev Deletes all records from the yield rate chronological array for a given group.
     * @param groupId The ID of the group to delete the array for.
     */
    function deleteYieldRates(uint256 groupId) external onlyRole(HARNESS_ADMIN_ROLE) {
        delete _yieldStreamerStorage().yieldRates[uint32(groupId)];
    }

    /**
     * @dev Sets the yield state for an account.
     * @param account The address of the account to set the yield state.
     * @param newState The new yield state to set for the account.
     */
    function setYieldState(address account, YieldState calldata newState) external onlyRole(HARNESS_ADMIN_ROLE) {
        _yieldStreamerStorage().yieldStates[account] = newState;
    }

    /**
     * @dev Resets the yield state to default values for an account.
     * @param account The address of the account to reset the yield state.
     */
    function resetYieldState(address account) external onlyRole(HARNESS_ADMIN_ROLE) {
        delete _yieldStreamerStorage().yieldStates[account];
    }

    /**
     * @dev Sets the current block time that should be used by the contract in certain conditions.
     * @param day The new day index starting from the Unix epoch to set.
     * @param time The new time in seconds starting from the beginning of the day to set.
     */
    function setBlockTimestamp(uint256 day, uint256 time) external onlyRole(HARNESS_ADMIN_ROLE) {
        YieldStreamerHarnessLayout storage harnessStorage = _yieldStreamerHarnessStorage();
        harnessStorage.currentBlockTimestamp = (day * (24 * 60 * 60) + time).toUint40();
    }

    /**
     * @dev Sets the boolean variable that defines whether the special block timestamp is used in the contract
     * @param newValue If true the special block timestamp is used. Otherwise the real block timestamp is used
     */
    function setUsingSpecialBlockTimestamps(bool newValue) external onlyRole(HARNESS_ADMIN_ROLE) {
        YieldStreamerHarnessLayout storage harnessStorage = _yieldStreamerHarnessStorage();
        harnessStorage.usingSpecialBlockTimestamps = newValue;
    }

    // ------------------ View functions -------------------------- //

    /// @dev Returns the current harness storage layout.
    function getHarnessStorageLayout() external pure returns (YieldStreamerHarnessLayout memory) {
        return _yieldStreamerHarnessStorage();
    }

    // ------------------ Overrides ------------------------------- //

    /// @dev Returns the current block timestamp according to the contract settings: a real one or a special one
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
     * @dev The function to access the namespaced storage of the harness contract.
     * @return $ The yield streamer harness storage layout, see {YieldStreamerHarnessLayout}.
     */
    function _yieldStreamerHarnessStorage() internal pure returns (YieldStreamerHarnessLayout storage $) {
        assembly {
            $.slot := _YIELD_STREAMER_HARNESS_STORAGE_LOCATION
        }
    }
}
