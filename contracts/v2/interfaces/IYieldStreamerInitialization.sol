// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IYieldStreamerInitialization_Types {
    enum InitializationMode {
        Preset,
        Migration
    }
}

interface IYieldStreamerInitialization_Errors {
    error YieldStreamer_AccountAlreadyInitialized(address account);
    error YieldStreamer_AccountInitializationProhibited(address account);
    error YieldStreamer_GroupForInitializationInvalid();
    error YieldStreamer_SourceYieldStreamerNotConfigured();
}

interface IYieldStreamerInitialization_Events {
    event YieldStreamer_AccountInitialized(
        address indexed account,
        uint256 indexed grouId,
        uint256 accruedYield,
        uint256 streamYield
    );

    event YieldStreamer_SourceYieldStreamerChanged(
        address newSourceYieldStreamer, // Tools: this comment prevents Prettier from formatting into a single line.
        address oldSourceYieldStreamer
    );
}

interface IYieldStreamerInitialization_Functions is IYieldStreamerInitialization_Types {
    function initializeAccountBatch(
        uint256 groupId,
        InitializationMode mode,
        uint256 startYieldOrParameter,
        address[] calldata accounts
    ) external;

    function setSourceYieldStreamer(address newSourceYieldStreamer) external;
}

interface IYieldStreamerInitialization is
    IYieldStreamerInitialization_Types,
    IYieldStreamerInitialization_Errors,
    IYieldStreamerInitialization_Events,
    IYieldStreamerInitialization_Functions
{}
