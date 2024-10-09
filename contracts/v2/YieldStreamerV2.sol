// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { AccessControlExtUpgradeable } from "./base/AccessControlExtUpgradeable.sol";
import { PausableExtUpgradeable } from "./base/PausableExtUpgradeable.sol";
import { RescuableUpgradeable } from "./base/RescuableUpgradeable.sol";

import { IYieldStreamerPrimary } from "./interfaces/IYieldStreamerPrimary.sol";
import { IYieldStreamerPrimary_Functions } from "./interfaces/IYieldStreamerPrimary.sol";
import { IYieldStreamerConfiguration } from "./interfaces/IYieldStreamerConfiguration.sol";
import { IYieldStreamerConfiguration_Functions } from "./interfaces/IYieldStreamerConfiguration.sol";

import { YieldStreamerStorage } from "./YieldStreamerStorage.sol";
import { YieldStreamerPrimary } from "./YieldStreamerPrimary.sol";
import { YieldStreamerConfiguration } from "./YieldStreamerConfiguration.sol";

contract YieldStreamerV2 is
    AccessControlExtUpgradeable,
    PausableExtUpgradeable,
    RescuableUpgradeable,
    UUPSUpgradeable,
    YieldStreamerPrimary,
    YieldStreamerConfiguration,
    IYieldStreamerPrimary,
    IYieldStreamerConfiguration
{
    // ------------------ Constants ------------------ //

    /// @dev The role of this contract owner.
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    /// @dev The role of this contract admin.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ------------------ Errors ------------------ //

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

    // ------------------ IYieldStreamerPrimary ------------------//

    function claimAllFor(address account) external onlyRole(ADMIN_ROLE) {
        _claimAllFor(account);
    }

    function claimAmountFor(address account, uint256 amount) external onlyRole(ADMIN_ROLE) {
        _claimAmountFor(account, amount);
    }

    function getYieldState(address account) external view returns (YieldState memory) {
        return _getYieldState(account);
    }

    function getClaimPreview(address account) external view returns (ClaimPreview memory) {
        return _getClaimPreview(account);
    }

    function getAccruePreview(address account) external view returns (AccruePreview memory) {
        return _getAccruePreview(account);
    }

    // ------------------ IYieldStreamerConfiguration ------------------//

    function assignGroup(
        uint32 groupId, // Tools: this comment prevents Prettier from formatting into a single line.
        address[] memory accounts,
        bool accrueYield
    ) external onlyRole(OWNER_ROLE) {
        _assignGroup(groupId, accounts, accrueYield);
    }

    function addYieldRate(
        uint32 groupId, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 effectiveDay,
        uint256 rateValue
    ) external onlyRole(OWNER_ROLE) {
        _addYieldRate(groupId, effectiveDay, rateValue);
    }

    function updateYieldRate(
        uint32 groupId,
        uint256 effectiveDay,
        uint256 rateValue,
        uint256 recordIndex
    ) external onlyRole(OWNER_ROLE) {
        _updateYieldRate(groupId, effectiveDay, rateValue, recordIndex);
    }

    // ------------------ Overrides ------------------ //

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

    // ------------------ Upgrade Authorization ------------------ //


    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(OWNER_ROLE) {
        newImplementation;
    }
}
