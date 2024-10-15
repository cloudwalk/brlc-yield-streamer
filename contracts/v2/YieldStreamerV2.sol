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

    /**
     * @inheritdoc IYieldStreamerPrimary_Functions
     */
    function getGroupYieldRates(uint256 groupId) external view returns (YieldRate[] memory) {
        return _getGroupYieldRates(groupId);
    }

    /**
     * @inheritdoc IYieldStreamerPrimary_Functions
     */
    function getAccountGroup(address account) external view returns (uint256) {
        return _getAccountGroup(account);
    }

    /**
     * @inheritdoc IYieldStreamerPrimary_Functions
     */
    function underlyingToken() external view returns (address) {
        return _underlyingToken();
    }

    /**
     * @inheritdoc IYieldStreamerPrimary_Functions
     */
    function feeReceiver() external view returns (address) {
        return _feeReceiver();
    }

    /**
     * @inheritdoc IYieldStreamerPrimary_Functions
     */
    function blockTimestamp() external view returns (uint256) {
        return _blockTimestamp();
    }

    // ------------------ IYieldStreamerConfiguration ------------- //

    /**
     * @inheritdoc IYieldStreamerConfiguration_Functions
     */
    function assignGroup(
        uint256 groupId, // Tools: this comment prevents Prettier from formatting into a single line.
        address[] memory accounts,
        bool forceYieldAccrue
    ) external onlyRole(OWNER_ROLE) {
        _assignMultipleAccountsToGroup(groupId, accounts, forceYieldAccrue);
    }

    /**
     * @inheritdoc IYieldStreamerConfiguration_Functions
     */
    function addYieldRate(
        uint256 groupId, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 effectiveDay,
        uint256 rateValue
    ) external onlyRole(OWNER_ROLE) {
        _addYieldRate(groupId, effectiveDay, rateValue);
    }

    /**
     * @inheritdoc IYieldStreamerConfiguration_Functions
     */
    function updateYieldRate(
        uint256 groupId,
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
    function initializeAccounts(address[] calldata accounts) external onlyRole(OWNER_ROLE) {
        _initializeMultipleAccounts(accounts);
    }

    /**
     * @inheritdoc IYieldStreamerInitialization_Functions
     */
    function setSourceYieldStreamer(address sourceYieldStreamer) external onlyRole(OWNER_ROLE) {
        _setSourceYieldStreamer(sourceYieldStreamer);
    }

    /**
     * @inheritdoc IYieldStreamerInitialization_Functions
     */
    function mapSourceYieldStreamerGroup(bytes32 groupKey, uint256 groupId) external onlyRole(OWNER_ROLE) {
        _mapSourceYieldStreamerGroup(groupKey, groupId);
    }

    /**
     * @inheritdoc IYieldStreamerInitialization_Functions
     */
    function setInitializedFlag(address account, bool isInitialized) external onlyRole(OWNER_ROLE) {
        _setInitializedFlag(account, isInitialized);
    }

    /**
     * @inheritdoc IYieldStreamerInitialization_Functions
     */
    function sourceYieldStreamer() external view returns (address) {
        return _sourceYieldStreamer();
    }

    // ------------------ Overrides ------------------------------- //

    /**
     * @inheritdoc YieldStreamerPrimary
     */
    function _accrueYield(address account) internal override(YieldStreamerPrimary, YieldStreamerConfiguration) {
        YieldStreamerPrimary._accrueYield(account);
    }

    /**
     * @inheritdoc YieldStreamerPrimary
     */
    function _blockTimestamp()
        internal
        view
        virtual
        override(YieldStreamerPrimary, YieldStreamerConfiguration, YieldStreamerInitialization)
        returns (uint256)
    {
        return YieldStreamerPrimary._blockTimestamp();
    }

    /**
     * @inheritdoc YieldStreamerInitialization
     */
    function _initializeSingleAccount(
        address account
    ) internal override(YieldStreamerPrimary, YieldStreamerInitialization) {
        YieldStreamerInitialization._initializeSingleAccount(account);
    }

    /**
     * @inheritdoc YieldStreamerConfiguration
     */
    function _assignSingleAccountToGroup(
        uint256 groupId, // Tools: this comment prevents Prettier from formatting into a single line.
        address account
    ) internal override(YieldStreamerConfiguration, YieldStreamerInitialization) {
        YieldStreamerConfiguration._assignSingleAccountToGroup(groupId, account);
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
