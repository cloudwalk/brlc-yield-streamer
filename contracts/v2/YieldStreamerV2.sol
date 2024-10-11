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
import { IYieldStreamerInitialization } from "./interfaces/IYieldStreamerInitialization.sol";
import { IYieldStreamerInitialization_Functions } from "./interfaces/IYieldStreamerInitialization.sol";

import { YieldStreamerStorage } from "./YieldStreamerStorage.sol";
import { YieldStreamerPrimary } from "./YieldStreamerPrimary.sol";
import { YieldStreamerConfiguration } from "./YieldStreamerConfiguration.sol";
import { YieldStreamerInitialization } from "./YieldStreamerInitialization.sol";

/**
 * @title YieldStreamerV2 contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev The contract that combines the primary, configuration and initialization contracts.
 */
contract YieldStreamerV2 is
    UUPSUpgradeable,
    AccessControlExtUpgradeable,
    PausableExtUpgradeable,
    RescuableUpgradeable,
    YieldStreamerPrimary,
    YieldStreamerConfiguration,
    YieldStreamerInitialization,
    IYieldStreamerPrimary,
    IYieldStreamerConfiguration,
    IYieldStreamerInitialization
{
    // ------------------ Constants ------------------------------- //

    /// @dev The role of this contract owner.
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    /// @dev The role of this contract admin.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // ------------------ Errors ---------------------------------- //

    error YieldStreamer_TokenAddressZero();

    // ------------------ Initializers ---------------------------- //

    /**
     * @dev Initializer of the upgradable contract.
     *
     * See details https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable.
     *
     * @param underlyingToken The address of the token to set as the underlying one.
     */
    function initialize(address underlyingToken) external initializer {
        __YieldStreamer_init(underlyingToken);
    }

    /**
     * @dev Internal initializer of the upgradable contract.
     *
     * See details https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable.
     *
     * @param underlyingToken The address of the token to set as the underlying one.
     */
    function __YieldStreamer_init(address underlyingToken) internal onlyInitializing {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __AccessControlExt_init_unchained();
        __Pausable_init_unchained();
        __PausableExt_init_unchained(OWNER_ROLE);
        __Rescuable_init_unchained(OWNER_ROLE);
        __UUPSUpgradeable_init_unchained();

        __YieldStreamer_init_init_unchained(underlyingToken);
    }

    /**
     * @dev Unchained internal initializer of the upgradable contract.
     *
     * See details https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable.
     *
     * Requirements:
     *
     * - The passed address of the underlying token must not be zero.
     *
     * @param underlyingToken The address of the token to set as the underlying one.
     */
    function __YieldStreamer_init_init_unchained(address underlyingToken) internal onlyInitializing {
        if (underlyingToken == address(0)) {
            revert YieldStreamer_TokenAddressZero();
        }

        _yieldStreamerStorage().underlyingToken = underlyingToken;

        _setRoleAdmin(OWNER_ROLE, OWNER_ROLE);
        _setRoleAdmin(ADMIN_ROLE, OWNER_ROLE);
        _grantRole(OWNER_ROLE, _msgSender());
    }

    // ------------------ IYieldStreamerPrimary ------------------- //

    /**
     * @inheritdoc IYieldStreamerPrimary_Functions
     */
    function claimAmountFor(address account, uint256 amount) external onlyRole(ADMIN_ROLE) {
        _claimAmountFor(account, amount);
    }

    /**
     * @inheritdoc IYieldStreamerPrimary_Functions
     */
    function getYieldState(address account) external view returns (YieldState memory) {
        return _getYieldState(account);
    }

    /**
     * @inheritdoc IYieldStreamerPrimary_Functions
     */
    function getClaimPreview(address account) external view returns (ClaimPreview memory) {
        return _getClaimPreview(account);
    }

    /**
     * @inheritdoc IYieldStreamerPrimary_Functions
     */
    function getAccruePreview(address account) external view returns (AccruePreview memory) {
        return _getAccruePreview(account);
    }

    // ------------------ IYieldStreamerConfiguration ------------- //

    /**
     * @inheritdoc IYieldStreamerConfiguration_Functions
     */
    function assignGroup(
        uint32 groupId, // Tools: this comment prevents Prettier from formatting into a single line.
        address[] memory accounts,
        bool forceYieldAccrue
    ) external onlyRole(OWNER_ROLE) {
        _assignGroup(groupId, accounts, forceYieldAccrue);
    }

    /**
     * @inheritdoc IYieldStreamerConfiguration_Functions
     */
    function addYieldRate(
        uint32 groupId, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 effectiveDay,
        uint256 rateValue
    ) external onlyRole(OWNER_ROLE) {
        _addYieldRate(groupId, effectiveDay, rateValue);
    }

    /**
     * @inheritdoc IYieldStreamerConfiguration_Functions
     */
    function updateYieldRate(
        uint32 groupId,
        uint256 itemIndex,
        uint256 effectiveDay,
        uint256 rateValue
    ) external onlyRole(OWNER_ROLE) {
        _updateYieldRate(groupId, itemIndex, effectiveDay, rateValue);
    }

    /**
     * @inheritdoc IYieldStreamerConfiguration_Functions
     */
    function setFeeReceiver(address newFeeReceiver) external onlyRole(OWNER_ROLE) {
        _setFeeReceiver(newFeeReceiver);
    }

    // ------------------ IYieldStreamerInitialization ------------ //

    /**
     * @inheritdoc IYieldStreamerInitialization_Functions
     */
    function initializeYieldState(address[] memory accounts) external onlyRole(OWNER_ROLE) {
        _initializeYieldState(accounts);
    }

    /**
     * @inheritdoc IYieldStreamerInitialization_Functions
     */
    function initializeYieldState(address[] memory accounts, uint256[] memory yields) external onlyRole(OWNER_ROLE) {
        _initializeYieldState(accounts, yields);
    }

    /**
     * @inheritdoc IYieldStreamerInitialization_Functions
     */
    function setSourceYieldStreamer(address sourceYieldStreamer) external onlyRole(OWNER_ROLE) {
        _setSourceYieldStreamer(sourceYieldStreamer);
    }

    // ------------------ Overrides ------------------------------- //

    /**
     * @inheritdoc YieldStreamerInitialization
     */
    function _initializeYieldState(
        address account
    ) internal override(YieldStreamerPrimary, YieldStreamerInitialization) {
        YieldStreamerInitialization._initializeYieldState(account);
    }

    /**
     * @inheritdoc YieldStreamerPrimary
     */
    function _accrueYield(
        address account,
        YieldState storage state,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) internal override(YieldStreamerPrimary, YieldStreamerConfiguration) {
        YieldStreamerPrimary._accrueYield(account, state, fromTimestamp, toTimestamp);
    }

    /**
     * @inheritdoc YieldStreamerPrimary
     */
    function _blockTimestamp()
        internal
        view
        override(YieldStreamerPrimary, YieldStreamerConfiguration)
        returns (uint256)
    {
        return YieldStreamerPrimary._blockTimestamp();
    }

    // ------------------ Upgrade Authorization ------------------ //

    /**
     * @dev The upgrade authorization function for UUPSProxy.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(OWNER_ROLE) {
        newImplementation; // Suppresses a compiler warning about the unused variable.
    }
}