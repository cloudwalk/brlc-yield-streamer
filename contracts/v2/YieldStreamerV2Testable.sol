// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { YieldStreamerV2Harness } from "./YieldStreamerV2Harness.sol";

/**
 * @title YieldStreamerV2Testable contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev Implements additional functions to test private and internal functions of base contracts.
 */
contract YieldStreamerV2Testable is YieldStreamerV2Harness {

    // ------------------ Utility --------------------------------- //

    function roundDown(uint256 amount) external pure returns (uint256) {
        return _roundDown(amount);
    }

    function roundUp(uint256 amount) external pure returns (uint256) {
        return _roundUp(amount);
    }
}
