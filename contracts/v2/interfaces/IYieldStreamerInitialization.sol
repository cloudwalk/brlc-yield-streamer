// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IYieldStreamerInitialization_Types {
    // -------------------- Types -------------------- //

    enum InitializationMode {
        Uninitialized,
        Automatic,
        Manual
    }

    struct InitializationState {
        InitializationMode mode;
        uint64 timestamp;
        uint64 yield;
    }
}

interface IYieldStreamerInitialization_Events {
    // -------------------- Events -------------------- //

    event YieldStreamer_YieldStateInitializationFailed(address indexed hook, string reason, uint256 code, bytes data);

    event YieldStreamer_YieldStateInitialized(address indexed account, uint256 yield);

    event YieldStreamer_SourceYieldStreamerChanged(
        address indexed oldSourceYieldStreamer,
        address indexed newSourceYieldStreamer
    );
}

interface IYieldStreamerInitialization_Functions {
    // -------------------- Functions -------------------- //

    function initializeYieldState(address[] memory accounts) external;

    function initializeYieldState(address[] memory accounts, uint256[] memory yields) external;

    function setSourceYieldStreamer(address sourceYieldStreamer) external;
}

interface IYieldStreamerInitialization is
    IYieldStreamerInitialization_Types,
    IYieldStreamerInitialization_Events,
    IYieldStreamerInitialization_Functions
{}
