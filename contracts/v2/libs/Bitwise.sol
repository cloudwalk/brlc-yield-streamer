// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title Bitwise library
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Provides functions to manipulate bits.
 */
library Bitwise {
    /**
     * @dev Sets a bit at the given index.
     * @param flags The flags value to set the bit for.
     * @param bitIndex The index of the bit to set.
     * @return The flags with the bit set.
     */
    function setBit(uint8 flags, uint256 bitIndex) internal pure returns (uint8) {
        return uint8(flags | (1 << bitIndex));
    }

    /**
     * @dev Checks if a bit at the given index is set.
     * @param flags The flags value to check the bit for.
     * @param bitIndex The index of the bit to check.
     * @return True if the bit is set, false otherwise.
     */
    function isBitSet(uint8 flags, uint256 bitIndex) internal pure returns (bool) {
        return (flags & (1 << bitIndex)) != 0;
    }
}
