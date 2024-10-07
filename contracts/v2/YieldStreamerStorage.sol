// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { IYieldStreamerTypes } from "./interfaces/IYieldStreamerTypes.sol";


contract YieldStreamerStorage is IYieldStreamerTypes {
    uint240 public constant RATE_FACTOR = 10 ** 9;

    uint256 public constant NEGATIVE_TIME_SHIFT = 0;

    address public underlyingToken;

    mapping(address => bytes32) internal _groups;

    mapping(address => YieldState) public _yieldStates;

    mapping(bytes32 => YieldRate[]) internal _yieldRates;

}
