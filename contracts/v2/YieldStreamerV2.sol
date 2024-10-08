// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { YieldStreamerStorage } from "./YieldStreamerStorage.sol";
import { YieldStreamerPrimary } from "./YieldStreamerPrimary.sol";
import { YieldStreamerConfiguration } from "./YieldStreamerConfiguration.sol";

contract YieldStreamerV2 is YieldStreamerStorage, YieldStreamerPrimary, YieldStreamerConfiguration, UUPSUpgradeable {
    error YieldStreamer_TokenAddressZero();

    function initialize(address token_) external initializer {
        __YieldStreamer_init(token_);
    }

    function __YieldStreamer_init(address token_) internal onlyInitializing {
        __UUPSUpgradeable_init_unchained();
        __YieldStreamer_init_init_unchained(token_);
    }

    function __YieldStreamer_init_init_unchained(address token_) internal onlyInitializing {
        if (token_ == address(0)) {
            revert YieldStreamer_TokenAddressZero();
        }

        _yieldStreamerStorage().underlyingToken = token_;
    }

    function _accrueYield(
        address account,
        YieldState storage state,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) internal override(YieldStreamerPrimary, YieldStreamerConfiguration) {
        YieldStreamerPrimary._accrueYield(account, state, fromTimestamp, toTimestamp);
    }

    function _blockTimestamp()
        internal
        view
        override(YieldStreamerPrimary, YieldStreamerConfiguration)
        returns (uint256)
    {
        return YieldStreamerPrimary._blockTimestamp();
    }

    function _authorizeUpgrade(address newImplementation) internal view override {
        newImplementation;
    }
}
