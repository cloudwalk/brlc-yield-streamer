// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { AccessControlExtUpgradeable } from "./base/AccessControlExtUpgradeable.sol";
import { PausableExtUpgradeable } from "./base/PausableExtUpgradeable.sol";
import { RescuableUpgradeable } from "./base/RescuableUpgradeable.sol";

import { YieldStreamerStorage } from "./YieldStreamerStorage.sol";
import { YieldStreamerPrimary } from "./YieldStreamerPrimary.sol";
import { YieldStreamerConfiguration } from "./YieldStreamerConfiguration.sol";

contract YieldStreamerV2 is
    YieldStreamerStorage,
    AccessControlExtUpgradeable,
    YieldStreamerConfiguration,
    PausableExtUpgradeable,
    YieldStreamerPrimary,
    RescuableUpgradeable,
    UUPSUpgradeable
{

    error YieldStreamer_TokenAddressZero();

    function initialize(address token) external initializer {
        __YieldStreamer_init(token);
    }

    function __YieldStreamer_init(address token) internal onlyInitializing {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __AccessControlExt_init_unchained();
        __Pausable_init_unchained();
        __PausableExt_init_unchained(OWNER_ROLE);
        __Rescuable_init_unchained(OWNER_ROLE);
        __UUPSUpgradeable_init_unchained();

        __YieldStreamer_init_init_unchained(token);
    }

    function __YieldStreamer_init_init_unchained(address token) internal onlyInitializing {
        if (token == address(0)) {
            revert YieldStreamer_TokenAddressZero();
        }

        _yieldStreamerStorage().underlyingToken = token;

        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);
        _setRoleAdmin(ADMIN_ROLE, OWNER_ROLE);
        _grantRole(OWNER_ROLE, _msgSender());
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

    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(OWNER_ROLE) {
        newImplementation;
    }
}
