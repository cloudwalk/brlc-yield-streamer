// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title Bitwise Library
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Provides utility functions for bit manipulation on an 8-bit unsigned integer (`uint8`).
 * This library includes functions to set, clear, and check individual bits within a byte.
 */
library Bitwise {
    // ------------------ Errors ---------------------------------- //

    /// @dev Thrown when the provided bit index is out of the valid range (0-7).
    error Bitwise_BitIndexOutOfBounds();

    // ------------------ Functions ------------------------------- //

    /**
     * @dev Sets (to 1) the bit at the specified index in a `uint8` value.
     * Performs a bitwise OR operation to set the bit at `bitIndex` to 1.
     *
     * Requirements:
     *
     * - `bitIndex` must be between 0 and 7 inclusive.
     *
     * Reverts:
     *
     * - `Bitwise_BitIndexOutOfBounds` if `bitIndex` is greater than or equal to 8.
     *
     * @param flags The original `uint8` value representing the flags.
     * @param bitIndex The index of the bit to set (0 for least significant bit).
     * @return The new `uint8` value with the specified bit set.
     */
    function setBit(uint8 flags, uint256 bitIndex) internal pure returns (uint8) {
        if (bitIndex >= 8) {
            revert Bitwise_BitIndexOutOfBounds();
        }

        return uint8(flags | (1 << bitIndex));
    }

    /**
     * @dev Clears (to 0) the bit at the specified index in a `uint8` value.
     * Performs a bitwise AND operation with the complement to set the bit at `bitIndex` to 0.
     *
     * Requirements:
     *
     * - `bitIndex` must be between 0 and 7 inclusive.
     *
     * Reverts:
     *
     * - `Bitwise_BitIndexOutOfBounds` if `bitIndex` is greater than or equal to 8.
     *
     * @param flags The original `uint8` value representing the flags.
     * @param bitIndex The index of the bit to clear (0 for least significant bit).
     * @return The new `uint8` value with the specified bit cleared.
     */
    function clearBit(uint8 flags, uint256 bitIndex) internal pure returns (uint8) {
        if (bitIndex >= 8) {
            revert Bitwise_BitIndexOutOfBounds();
        }

        return uint8(flags & ~(1 << bitIndex));
    }

    /**
     * @dev Checks whether the bit at the specified index in a `uint8` value is set (1) or not (0).
     * Performs a bitwise AND operation and checks if the result is non-zero.
     *
     * Requirements:
     *
     * - `bitIndex` must be between 0 and 7 inclusive.
     *
     * Reverts:
     *
     * - `Bitwise_BitIndexOutOfBounds` if `bitIndex` is greater than or equal to 8.
     *
     * @param flags The `uint8` value representing the flags.
     * @param bitIndex The index of the bit to check (0 for least significant bit).
     * @return True if the specified bit is set (1), false if it is cleared (0).
     */
    function isBitSet(uint8 flags, uint256 bitIndex) internal pure returns (bool) {
        if (bitIndex >= 8) {
            revert Bitwise_BitIndexOutOfBounds();
        }

        return (flags & (1 << bitIndex)) != 0;
    }
}
