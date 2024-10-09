// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20Hook } from "../../../interfaces/IERC20Hook.sol";
/**
 * @title ERC20TokenMock contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev An implementation of the {ERC20} contract for testing purposes.
 */
contract ERC20TokenMock is ERC20 {
    // ------------------ Storage---- ----------------------------- //

    address private _hook;

    // ------------------ Constructor ----------------------------- //

    /**
     * @dev The constructor of the contract.
     * @param name_ The name of the token to set for this ERC20-comparable contract.
     * @param symbol_ The symbol of the token to set for this ERC20-comparable contract.
     */
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    // ------------------ Functions ------------------------------- //

    /**
     * @dev Calls the appropriate internal function to mint needed amount of tokens for an account.
     * @param account The address of an account to mint for.
     * @param amount The amount of tokens to mint.
     */
    function mint(address account, uint256 amount) external returns (bool) {
        _mint(account, amount);

        if (_hook != address(0)) {
            IERC20Hook(_hook).afterTokenTransfer(address(0), account, amount);
        }

        return true;
    }

    /**
     * @dev Calls the appropriate internal function to burn needed amount of tokens for an account.
     * @param account The address of an account to burn for.
     * @param amount The amount of tokens to burn.
     */
    function burn(address account, uint256 amount) external returns (bool) {
        _burn(account, amount);

        if (_hook != address(0)) {
            IERC20Hook(_hook).afterTokenTransfer(account, address(0), amount);
        }

        return true;
    }

    /**
     * @dev Sets the address of the hook.
     * @param hook The address of the hook to set.
     */
    function setHook(address hook) external returns (bool) {
        _hook = hook;
        return true;
    }
}
