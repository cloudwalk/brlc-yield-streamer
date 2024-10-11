// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library Utils {
    // ------------------ Functions ------------------ //
    function _isBitSet(uint256 flags, uint256 bitIndex) internal pure returns (bool) {
        return (flags & bitIndex) != 0;
    }
}
