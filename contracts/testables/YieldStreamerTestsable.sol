// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { YieldStreamer } from "../YieldStreamer.sol";

/**
 * @title YieldStreamerTestable contract
 * @author CloudWalk Inc. (See https://cloudwalk.io)
 * @dev The version of the yield streamer contract with additions required for testing.
 */
contract YieldStreamerTestable is YieldStreamer {
    /**
     * @notice Sets the stop streaming timestamp for a given account.
     *
     * @param account The address of the account to set the stop streaming timestamp for.
     * @param timestamp The timestamp to set the stop streaming timestamp to.
     */
    function setStreamingStopTimestamp(address account, uint256 timestamp) external {
        _stopStreamingAt[account] = timestamp;
    }
}
