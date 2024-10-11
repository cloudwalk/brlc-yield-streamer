// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IYieldStreamerV1Blocklistable {
    /**
     * @notice Adds an account to the blocklist
     * @param account The address to blocklist
     */
    function blocklist(address account) external;

    /**
     * @notice Removes an account from the blocklist
     * @param account The address to remove from the blocklist
     */
    function unBlocklist(address account) external;

    /**
     * @notice Checks if the account is a blocklister
     *
     * @param account The address to check for blocklister configuration
     * @return True if the account is a configured blocklister, False otherwise
     */
    function isBlocklister(address account) external view returns (bool);
}
