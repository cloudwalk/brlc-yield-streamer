// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { Bitwise } from "./libs/Bitwise.sol";
import { YieldStreamerStorage } from "./YieldStreamerStorage.sol";
import { IYieldStreamerPrimary_Errors } from "./interfaces/IYieldStreamerPrimary.sol";
import { IYieldStreamerPrimary_Events } from "./interfaces/IYieldStreamerPrimary.sol";
import { IERC20Hook } from "../interfaces/IERC20Hook.sol";
import { Versionable } from "./base/Versionable.sol";

/**
 * @title YieldStreamerPrimary contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev The contract that responsible for the yield calculation and distribution.
 */
abstract contract YieldStreamerPrimary is
    YieldStreamerStorage,
    IYieldStreamerPrimary_Errors,
    IYieldStreamerPrimary_Events,
    IERC20Hook,
    Versionable
{
    // -------------------- Libraries ----------------------------- //

    using SafeCast for uint256;
    using Bitwise for uint8;

    // -------------------- Structs ------------------------------- //

    /**
     * @dev Structure representing the parameters for calculating the compound yield over a period.
     *
     * Attributes:
     * - `fromTimestamp`: The starting timestamp of the calculation period.
     * - `toTimestamp`: The ending timestamp of the calculation period.
     * - `tiers`: The yield tiers to apply during the calculation period.
     * - `balance`: The balance amount to calculate the yield on.
     * - `streamYield`: The prior stream yield amount before this calculation.
     */
    struct CompoundYieldParams {
        uint256 fromTimestamp;
        uint256 toTimestamp;
        RateTier[] tiers;
        uint256 balance;
        uint256 streamYield;
    }

    /**
     * @dev Structure representing the parameters for calculating yield over a period with multiple rates.
     *
     * Attributes:
     * - `fromTimestamp`: The starting timestamp of the calculation period.
     * - `toTimestamp`: The ending timestamp of the calculation period.
     * - `rateStartIndex`: The starting index of the yield rates array for the period.
     * - `rateEndIndex`: The ending index of the yield rates array for the period.
     * - `initialBalance`: The balance at the beginning of the calculation period.
     * - `initialStreamYield`: The stream yield amount at the beginning of the calculation period.
     * - `initialAccruedYield`: The accrued yield amount at the beginning of the calculation period.
     */
    struct CalculateYieldParams {
        uint256 fromTimestamp;
        uint256 toTimestamp;
        uint256 rateStartIndex;
        uint256 rateEndIndex;
        uint256 initialBalance;
        uint256 initialStreamYield;
        uint256 initialAccruedYield;
    }

    // -------------------- Modifiers ----------------------------- //

    /**
     * @dev Modifier to ensure the caller is the underlying token contract.
     */
    modifier onlyToken() {
        if (msg.sender != _yieldStreamerStorage().underlyingToken) {
            revert YieldStreamer_HookCallerUnauthorized();
        }
        _;
    }

    // -------------------- IERC20Hook ---------------------------- //

    /**
     * @inheritdoc IERC20Hook
     */
    function beforeTokenTransfer(address from, address to, uint256 amount) external {
        // No action required before the token transfer.
    }

    /**
     * @inheritdoc IERC20Hook
     */
    function afterTokenTransfer(address from, address to, uint256 amount) external onlyToken {
        if (from != address(0)) {
            _decreaseTokenBalance(from, amount);
        }
        if (to != address(0)) {
            _increaseTokenBalance(to, amount);
        }
    }

    // -------------------- Functions ------------------------------ //

    /**
     * @dev Claims a specified amount of accrued yield for an account.
     * Transfers the specified amount of yield (after deducting any applicable fees) to the account.
     *
     * @param account The address of the account for which to claim yield.
     * @param amount The amount of yield to claim.
     */
    function _claimAmountFor(address account, uint256 amount) internal {
        if (amount < MIN_CLAIM_AMOUNT) {
            revert YieldStreamer_ClaimAmountBelowMinimum();
        }
        if (amount != _roundDown(amount)) {
            revert YieldStreamer_ClaimAmountNonRounded();
        }

        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldState storage state = $.yieldStates[account];

        if (!state.flags.isBitSet(uint256(YieldStateFlagIndex.Initialized))) {
            revert YieldStreamer_AccountNotInitialized();
        }

        YieldRate[] storage yieldRates = $.yieldRates[$.groups[account].id];

        _accrueYield(account, state, yieldRates);
        _transferYield(account, amount, state, $.feeReceiver, $.underlyingToken);
    }

    /**
     * @dev Increases the token balance of a given account after a token transfer.
     *
     * @param account The account whose token balance will be increased.
     * @param amount The amount by which to increase the token balance.
     */
    function _increaseTokenBalance(address account, uint256 amount) private {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldState storage state = $.yieldStates[account];

        if (state.flags.isBitSet(uint256(YieldStateFlagIndex.Initialized)) || _tryInitializeAccount(account, state)) {
            if (state.lastUpdateTimestamp != _blockTimestamp()) {
                YieldRate[] storage yieldRates = $.yieldRates[$.groups[account].id];
                _accrueYield(account, state, yieldRates);
            }
            state.lastUpdateBalance += amount.toUint64();
        }
    }

    /**
     * @dev Decreases the token balance of a given account after a token transfer.
     *
     * @param account The account whose token balance will be decreased.
     * @param amount The amount by which to decrease the token balance.
     */
    function _decreaseTokenBalance(address account, uint256 amount) private {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldState storage state = $.yieldStates[account];

        if (state.flags.isBitSet(uint256(YieldStateFlagIndex.Initialized)) || _tryInitializeAccount(account, state)) {
            if (state.lastUpdateTimestamp != _blockTimestamp()) {
                YieldRate[] storage yieldRates = $.yieldRates[$.groups[account].id];
                _accrueYield(account, state, yieldRates);
            }
            state.lastUpdateBalance -= amount.toUint64();
        }
    }

    /**
     * @dev Attempts to initialize the yield state for an account if auto-initialization is enabled.
     * If the account is not initialized and auto-initialization is enabled, initializes the account.
     *
     * @param account The account to attempt initialization for.
     * @param state The yield state storage reference for the account.
     * @return True if the account was initialized by this function call; false otherwise.
     */
    function _tryInitializeAccount(address account, YieldState storage state) private returns (bool) {
        if (ENABLE_YIELD_STATE_AUTO_INITIALIZATION) {
            if (account != address(0) && account.code.length == 0) {
                _initializeSingleAccount(account);
                return state.flags.isBitSet(uint256(YieldStateFlagIndex.Initialized));
            }
        }
        return false;
    }

    /**
     * @dev Transfers the specified amount of yield to the account, after deducting any applicable fees.
     *
     * @param account The account receiving the yield.
     * @param amount The amount of yield to transfer before fees.
     * @param state The yield state storage reference for the account.
     * @param feeReceiver The address that will receive the fee.
     * @param token The address of the underlying token.
     */
    function _transferYield(
        address account,
        uint256 amount,
        YieldState storage state,
        address feeReceiver,
        address token
    ) private {
        uint256 totalYield = state.accruedYield + state.streamYield;

        if (amount > totalYield) {
            revert YieldStreamer_YieldBalanceInsufficient();
        }

        if (amount > state.accruedYield) {
            state.streamYield -= (amount - state.accruedYield).toUint64();
            state.accruedYield = 0;
        } else {
            state.accruedYield -= amount.toUint64();
        }

        uint256 fee = 0;
        if (FEE_RATE != 0) {
            if (feeReceiver == address(0)) {
                revert YieldStreamer_FeeReceiverNotConfigured();
            }
            fee = _roundUp(_calculateFee(amount));
            amount -= fee;
        }

        emit YieldStreamer_YieldTransferred(account, amount, fee);

        if (fee > 0) {
            IERC20(token).transfer(feeReceiver, fee);
        }
        IERC20(token).transfer(account, amount);
    }

    /**
     * @dev Retrieves the yield state for a given account.
     *
     * @param account The account to retrieve the yield state for.
     * @return The yield state of the account.
     */
    function _getYieldState(address account) internal view returns (YieldState memory) {
        return _yieldStreamerStorage().yieldStates[account];
    }

    /**
     * @dev Provides a preview of the claimable yield for a given account at the current time.
     * Calculates the yield that can be claimed without modifying the state.
     *
     * @param account The account to get the claim preview for.
     * @return A `ClaimPreview` struct containing details of the claimable yield.
     */
    function _getClaimPreview(address account, uint256 currentTimestamp) internal view returns (ClaimPreview memory) {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldState storage state = $.yieldStates[account];
        YieldRate[] storage yieldRates = $.yieldRates[$.groups[account].id];
        return _map(_getAccruePreview(state, yieldRates, currentTimestamp));
    }

    /**
     * @dev Provides a preview of the yield accrual for a given account.
     * Calculates how the yield will accrue over time without modifying the state.
     *
     * @param account The account to get the accrual preview for.
     * @return An `AccruePreview` struct containing details of the accrued yield.
     */
    function _getAccruePreview(address account, uint256 currentTimestamp) internal view returns (AccruePreview memory) {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldState storage state = $.yieldStates[account];
        YieldRate[] storage yieldRates = $.yieldRates[$.groups[account].id];
        return _getAccruePreview(state, yieldRates, currentTimestamp);
    }

    /**
     * @dev Generates an accrue preview for a given account based on its current yield state and yield rates.
     * Provides detailed information about the yield accrual without modifying the state.
     *
     * @param state The current yield state of the account.
     * @param yieldRates The yield rates to use for the calculation.
     * @return An `AccruePreview` struct containing details of the accrued yield.
     */
    function _getAccruePreview(
        YieldState memory state,
        YieldRate[] memory yieldRates,
        uint256 currentTimestamp
    ) public pure returns (AccruePreview memory) {
        AccruePreview memory preview;

        preview.balance = state.lastUpdateBalance;
        preview.streamYieldBefore = state.streamYield;
        preview.accruedYieldBefore = state.accruedYield;
        preview.fromTimestamp = state.lastUpdateTimestamp;
        preview.toTimestamp = currentTimestamp;

        (uint256 rateStartIndex, uint256 rateEndIndex) = _inRangeYieldRates(
            yieldRates,
            preview.fromTimestamp,
            preview.toTimestamp
        );

        CalculateYieldParams memory calculateParams = CalculateYieldParams(
            preview.fromTimestamp,
            preview.toTimestamp,
            rateStartIndex,
            rateEndIndex,
            state.lastUpdateBalance,
            preview.streamYieldBefore,
            preview.accruedYieldBefore
        );

        YieldResult[] memory calculateResults = _calculateYield(calculateParams, yieldRates);
        (preview.accruedYieldAfter, preview.streamYieldAfter) = _aggregateYield(calculateResults);
        preview.accruedYieldAfter += preview.accruedYieldBefore;

        preview.rates = _truncateArray(rateStartIndex, rateEndIndex, yieldRates);
        preview.results = calculateResults;

        return preview;
    }

    /**
     * @dev Returns an array of yield rates associated with a specific group ID.
     *
     * @param groupId The ID of the group to get the yield rates for.
     * @return An array of `YieldRate` structs representing the yield rates.
     */
    function _getGroupYieldRates(uint256 groupId) internal view returns (YieldRate[] memory) {
        return _yieldStreamerStorage().yieldRates[groupId.toUint32()];
    }

    /**
     * @dev Returns the group ID that the specified account belongs to.
     *
     * @param account The account to get the group ID for.
     * @return The group ID of the account.
     */
    function _getAccountGroup(address account) internal view returns (uint256) {
        return _yieldStreamerStorage().groups[account].id;
    }

    /**
     * @dev Returns the address of the underlying token used by the yield streamer.
     *
     * @return The address of the underlying token contract.
     */
    function _underlyingToken() internal view returns (address) {
        return _yieldStreamerStorage().underlyingToken;
    }

    /**
     * @dev Returns the address of the fee receiver for the yield streamer.
     *
     * @return The address of the fee receiver.
     */
    function _feeReceiver() internal view returns (address) {
        return _yieldStreamerStorage().feeReceiver;
    }

    // ------------------ Yield calculation ----------------------- //

    /**
     * @dev Accrues the yield for a given account.
     * Calculates the new accrued yield and stream yield based on the time elapsed and updates the yield state.
     *
     * @param account The account to accrue the yield for.
     */
    function _accrueYield(address account) internal virtual {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldState storage state = $.yieldStates[account];
        YieldRate[] storage yieldRates = $.yieldRates[$.groups[account].id];
        _accrueYield(account, state, yieldRates);
    }

    /**
     * @dev Accrues the yield for a given account and period.
     * Calculates the new accrued yield and stream yield based on the time elapsed and updates the yield state.
     *
     * @param account The account to accrue the yield for.
     * @param state The current yield state of the account.
     * @param yieldRates The yield rates to use for the calculation.
     */
    function _accrueYield(
        address account, // Tools: this comment prevents Prettier from formatting into a single line.
        YieldState storage state,
        YieldRate[] storage yieldRates
    ) private {
        uint256 currentTimestamp = _blockTimestamp();
        AccruePreview memory preview = _getAccruePreview(state, yieldRates, currentTimestamp);

        emit YieldStreamer_YieldAccrued(
            account,
            preview.accruedYieldAfter,
            preview.streamYieldAfter,
            preview.accruedYieldBefore,
            preview.streamYieldBefore
        );

        state.streamYield = preview.streamYieldAfter.toUint64();
        state.accruedYield = preview.accruedYieldAfter.toUint64();
        state.lastUpdateTimestamp = preview.toTimestamp.toUint40();
    }

    /**
     * @dev Calculates the yield for a given period using provided yield rates.
     * This function handles multiple yield rate periods that may overlap with the specified time range.
     * It divides the overall time range into sub-periods based on the effective days of the yield rates
     * and calculates the yield for each sub-period individually using the `_compoundYield` function.
     *
     * @param params The parameters required for yield calculation, including:
     *   - `fromTimestamp`: The start of the yield calculation period.
     *   - `toTimestamp`: The end of the yield calculation period.
     *   - `rateStartIndex`: The index of the first relevant yield rate in the `yieldRates` array.
     *   - `rateEndIndex`: The index of the last relevant yield rate in the `yieldRates` array.
     *   - `initialBalance`: The initial balance amount to calculate yield on.
     *   - `initialStreamYield`: Any prior stream yield to include in the first calculation.
     *   - `initialAccruedYield`: Any prior accrued yield to include in the calculations.
     * @param yieldRates The array of `YieldRate` structs that contain the yield rate tiers and their effective days.
     * @return results An array of `YieldResult` structs, each representing the yield calculated for a sub-period.
     */
    function _calculateYield(
        CalculateYieldParams memory params,
        YieldRate[] memory yieldRates
    ) internal pure returns (YieldResult[] memory results) {
        uint256 ratePeriods = params.rateEndIndex - params.rateStartIndex + 1;
        uint256 localFromTimestamp = params.fromTimestamp;
        uint256 localToTimestamp = params.toTimestamp;

        /**
         * At this point, we ensure that the `rates` array contains at least one yield rate
         * that fully covers the period from `fromTimestamp` to `toTimestamp`. Hence, no additional
         * validation on the rates or the time range is necessary.
         */

        if (ratePeriods == 1) {
            /**
             * Scenario 1: Single Yield Rate Period
             * If there's only one yield rate applicable for the entire time range, we calculate the yield
             * for the entire period using this one rate.
             *
             * Steps:
             * 1. Initialize the `results` array with a single `YieldResult`.
             * 2. Call `_compoundYield` with the current time range and the applicable yield rate tiers.
             * 3. Store the calculated yield in the `results` array.
             */
            results = new YieldResult[](1);
            results[0] = _compoundYield(
                CompoundYieldParams(
                    localFromTimestamp,
                    localToTimestamp,
                    yieldRates[params.rateStartIndex].tiers,
                    params.initialBalance + params.initialAccruedYield,
                    params.initialStreamYield
                )
            );
        } else if (ratePeriods == 2) {
            /**
             * Scenario 2: Two Yield Rate Periods
             * When the time range spans two different yield rate periods, we need to calculate the yield
             * separately for each sub-period.
             *
             * Steps:
             * 1. Initialize the `results` array with two `YieldResult` entries.
             * 2. For the first sub-period:
             *    a. Set `localFromTimestamp` to `params.fromTimestamp`.
             *    b. Set `localToTimestamp` to the start of the second yield rate period.
             *    c. Calculate the yield using the first yield rate's tiers.
             * 3. For the second sub-period:
             *    a. Update `localFromTimestamp` to the start of the second yield rate period.
             *    b. Set `localToTimestamp` to `params.toTimestamp`.
             *    c. Calculate the yield using the second yield rate's tiers.
             * 4. Accumulate the results accordingly.
             */

            results = new YieldResult[](2);

            /**
             * Calculate yield for the first yield rate period.
             */

            localFromTimestamp = params.fromTimestamp;
            localToTimestamp = uint256(yieldRates[params.rateStartIndex + 1].effectiveDay) * 1 days;

            results[0] = _compoundYield(
                CompoundYieldParams(
                    localFromTimestamp,
                    localToTimestamp,
                    yieldRates[params.rateStartIndex].tiers,
                    params.initialBalance + params.initialAccruedYield,
                    params.initialStreamYield
                )
            );

            /**
             * Calculate yield for the second yield rate period.
             */

            localFromTimestamp = localToTimestamp;
            localToTimestamp = params.toTimestamp;

            results[1] = _compoundYield(
                CompoundYieldParams(
                    localFromTimestamp,
                    localToTimestamp,
                    yieldRates[params.rateStartIndex + 1].tiers,
                    params.initialBalance +
                        params.initialAccruedYield +
                        results[0].firstDayPartialYield +
                        results[0].fullDaysYield +
                        results[0].lastDayPartialYield,
                    0
                )
            );
        } else {
            /**
             * Scenario 3: Multiple Yield Rate Periods
             * When the time range spans more than two yield rate periods, we must divide the period into
             * multiple sub-periods, each corresponding to a different yield rate period.
             *
             * Steps:
             * 1. Initialize the `results` array with an entry for each yield rate period.
             * 2. For the first sub-period:
             *    a. Set `localFromTimestamp` to `params.fromTimestamp`.
             *    b. Set `localToTimestamp` to the start of the second yield rate period.
             *    c. Calculate the yield using the first yield rate's tiers.
             *    d. Update the `currentBalance` by adding the yield from this sub-period.
             * 3. For each intermediate sub-period:
             *    a. Set `localFromTimestamp` to the start of the current yield rate period.
             *    b. Set `localToTimestamp` to the start of the next yield rate period.
             *    c. Calculate the yield using the current yield rate's tiers.
             *    d. Update the `currentBalance` by adding the yield from this sub-period.
             * 4. For the last sub-period:
             *    a. Set `localFromTimestamp` to the start of the last yield rate period.
             *    b. Set `localToTimestamp` to `params.toTimestamp`.
             *    c. Calculate the yield using the last yield rate's tiers.
             */
            results = new YieldResult[](ratePeriods);
            uint256 currentBalance;

            /**
             * Calculate yield for the first yield rate period.
             */

            localFromTimestamp = params.fromTimestamp;
            localToTimestamp = uint256(yieldRates[params.rateStartIndex + 1].effectiveDay) * 1 days;
            currentBalance = params.initialBalance + params.initialAccruedYield;

            results[0] = _compoundYield(
                CompoundYieldParams(
                    localFromTimestamp,
                    localToTimestamp,
                    yieldRates[params.rateStartIndex].tiers,
                    currentBalance,
                    params.initialStreamYield
                )
            );

            // Update the balance by adding the yield from the first sub-period.
            currentBalance +=
                results[0].firstDayPartialYield +
                results[0].fullDaysYield +
                results[0].lastDayPartialYield;

            /**
             * Calculate yield for the intermediate yield rate periods.
             */

            for (uint256 i = params.rateStartIndex + 1; i < params.rateEndIndex; i++) {
                localFromTimestamp = uint256(yieldRates[i].effectiveDay) * 1 days;
                localToTimestamp = uint256(yieldRates[i + 1].effectiveDay) * 1 days;

                results[i - params.rateStartIndex] = _compoundYield(
                    CompoundYieldParams(
                        localFromTimestamp, // Tools: this comment prevents Prettier from formatting into a single line.
                        localToTimestamp,
                        yieldRates[i].tiers,
                        currentBalance,
                        0
                    )
                );

                // Update the balance by adding the yield from the current sub-period.
                currentBalance +=
                    results[i - params.rateStartIndex].firstDayPartialYield +
                    results[i - params.rateStartIndex].fullDaysYield +
                    results[i - params.rateStartIndex].lastDayPartialYield;
            }

            /**
             * Calculate yield for the last yield rate period.
             */

            localFromTimestamp = uint256(yieldRates[params.rateStartIndex + ratePeriods - 1].effectiveDay) * 1 days;
            localToTimestamp = params.toTimestamp;

            results[ratePeriods - 1] = _compoundYield(
                CompoundYieldParams(
                    localFromTimestamp,
                    localToTimestamp,
                    yieldRates[params.rateStartIndex + ratePeriods - 1].tiers,
                    currentBalance,
                    0
                )
            );
        }

        /**
         * @dev Returns the array of `YieldResult` structs, each containing the yield calculations
         * for their respective sub-periods. These results can then be aggregated to understand
         * the total yield over the entire specified time range.
         */
        return results;
    }

    /**
     * @dev Calculates compounded yield over a specified time range using tiered rates.
     * The function handles three distinct periods:
     * 1. First partial day (if timestamp doesn't start at 00:00:00);
     * 2. Full intermediate days;
     * 3. Last partial day (if timestamp doesn't end at 00:00:00).
     *
     * For each period, yield is calculated per tier based on:
     * - Balance amount (which compounds after each full day);
     * - Rate tiers (each tier has a rate and optional cap);
     * - Time duration.
     *
     * @param params Contains:
     *   - fromTimestamp: Start time of yield calculation;
     *   - toTimestamp: End time of yield calculation;
     *   - tiers: Array of rate/cap pairs for tiered yield calculation;
     *   - balance: Initial balance to calculate yield on;
     *   - streamYield: Any prior yield to include in first calculation.
     * @return result A `YieldResult` struct containing:
     *   - Yield amounts for first partial day, full days, and last partial day;
     *   - Per-tier breakdown of yield for each period.
     */
    function _compoundYield(CompoundYieldParams memory params) internal pure returns (YieldResult memory result) {
        // Validate timestamps and balance.
        if (params.fromTimestamp > params.toTimestamp) {
            revert YieldStreamer_TimeRangeInvalid();
        }
        if (params.fromTimestamp == params.toTimestamp || params.balance == 0) {
            return result;
        }

        uint256 length = params.tiers.length;

        // Initialize arrays to track yield per tier for each period.
        result.tieredFirstDayPartialYield = new uint256[](length);
        result.tieredFullDaysYield = new uint256[](length);
        result.tieredLastDayPartialYield = new uint256[](length);

        /**
         * 1. First Partial Day Handling
         * There are 4 possible cases for the first day:
         */

        // Represents the start of the current day.
        uint256 fromTimestampEffective = _effectiveTimestamp(params.fromTimestamp);

        // Represents the start of the next day.
        uint256 nextDayTimestamp = fromTimestampEffective + 1 days;

        if (params.fromTimestamp != fromTimestampEffective) {
            // Case 1 & 2: Starting mid-day.
            if (params.toTimestamp <= nextDayTimestamp) {
                // Case 1: Both start and end within same partial day.
                // Example: D1 14:00 -> D1 18:00.
                (result.lastDayPartialYield, result.tieredLastDayPartialYield) = _calculateTieredYield(
                    params.balance,
                    params.toTimestamp - params.fromTimestamp,
                    params.tiers
                );
                result.lastDayPartialYield += params.streamYield;
                return result;
            } else {
                // Case 2: Start mid-day but continue to next day.
                // Example: D1 14:00 -> D2 18:00.
                (result.firstDayPartialYield, result.tieredFirstDayPartialYield) = _calculateTieredYield(
                    params.balance,
                    nextDayTimestamp - params.fromTimestamp,
                    params.tiers
                );
                result.firstDayPartialYield += params.streamYield;
                params.fromTimestamp = nextDayTimestamp; // Move to start of next day
            }
        } else if (params.toTimestamp < nextDayTimestamp) {
            // Case 3: Start at day start (00:00:00) but end within same day.
            // Example: D1 00:00 -> D1 18:00.
            (result.lastDayPartialYield, result.tieredLastDayPartialYield) = _calculateTieredYield(
                params.balance + params.streamYield,
                params.toTimestamp - params.fromTimestamp,
                params.tiers
            );
            result.firstDayPartialYield = params.streamYield;
            return result;
        } else {
            // Case 4: Start at day start and continue to next day.
            // Example: D1 00:00 -> D2 18:00.
            result.firstDayPartialYield = params.streamYield;
        }

        /**
         * 2. Full Days Handling
         * Calculate and compound yield for each complete day.
         */
        uint256 toTimestampEffective = _effectiveTimestamp(params.toTimestamp);
        uint256 fullDaysCount = (toTimestampEffective - params.fromTimestamp) / 1 days;
        params.balance += result.firstDayPartialYield; // Compound first day's yield.

        if (fullDaysCount > 0) {
            uint256 fullDayYield;
            uint256[] memory tieredFullDayYield = new uint256[](length);

            // For each full day, calculate yield and compound it into balance.
            for (uint256 i = 0; i < fullDaysCount; i++) {
                (fullDayYield, tieredFullDayYield) = _calculateTieredYield(params.balance, 1 days, params.tiers);

                // Accumulate per-tier yields.
                for (uint256 j = 0; j < length; j++) {
                    result.tieredFullDaysYield[j] += tieredFullDayYield[j];
                }

                params.balance += fullDayYield; // Compound the day's yield.
                result.fullDaysYield += fullDayYield;
            }

            params.fromTimestamp += fullDaysCount * 1 days;
        }

        /**
         * 3. Last Partial Day Handling
         * Calculate yield for any remaining time less than a full day.
         */
        if (params.fromTimestamp < params.toTimestamp) {
            (result.lastDayPartialYield, result.tieredLastDayPartialYield) = _calculateTieredYield(
                params.balance,
                params.toTimestamp - params.fromTimestamp,
                params.tiers
            );
        }

        /**
         * Return the final yield result.
         */
        return result;
    }

    /**
     * @dev Calculates the yield for a given period using tiered rates.
     *
     * @param amount The amount to calculate the yield for.
     * @param elapsedSeconds The elapsed seconds within the period.
     * @param rateTiers The yield tiers to apply during the calculation period.
     * @return totalYield The yield accrued during the period.
     * @return tieredYield The yield accrued during the period for each tier.
     */
    function _calculateTieredYield(
        uint256 amount,
        uint256 elapsedSeconds,
        RateTier[] memory rateTiers
    ) internal pure returns (uint256 totalYield, uint256[] memory tieredYield) {
        uint256 remainingAmount = amount;
        uint256 cappedAmount;
        uint256 yield;
        uint256 i;
        RateTier memory tier;
        uint256 length = rateTiers.length;

        // Initialize array to store yield for each tier.
        tieredYield = new uint256[](length);

        do {
            // If no amount remains to be processed, exit the loop.
            if (remainingAmount == 0) {
                break;
            }

            // Get current tier being processed.
            tier = rateTiers[i];

            // Determine how much of `remainingAmount` to process in this tier:
            // 1. If `tier.cap` is 0, process all remaining amount (0 means no cap);
            // 2. If remaining amount exceeds tier cap, process up to cap;
            // 3. Otherwise process entire remaining amount.
            if (tier.cap == 0) {
                cappedAmount = remainingAmount;
            } else if (remainingAmount > tier.cap) {
                cappedAmount = tier.cap;
            } else {
                cappedAmount = remainingAmount;
            }

            // Calculate yield for this tier's portion using simple interest formula.
            yield = _calculateSimpleYield(cappedAmount, tier.rate, elapsedSeconds);

            // Store yield for this specific tier.
            tieredYield[i] = yield;

            // Add this tier's yield to total and subtract processed amount.
            totalYield += yield;
            remainingAmount -= cappedAmount;

            // Move to next tier.
            i++;
        } while (i < length);

        return (totalYield, tieredYield);
    }

    /**
     * @dev Calculates a simple yield for a given period.
     *
     * @param amount The amount to calculate the yield for.
     * @param rate The rate to apply when calculating the yield.
     * @param elapsedSeconds The elapsed seconds within the period.
     * @return yield The yield accrued during the period.
     */
    function _calculateSimpleYield(
        uint256 amount,
        uint256 rate,
        uint256 elapsedSeconds
    ) internal pure returns (uint256 yield) {
        yield = (amount * rate * elapsedSeconds) / (1 days * RATE_FACTOR);
    }

    /**
     * @dev Finds the yield rates that overlap with the given timestamp range.
     *
     * @param yieldRates The array of yield rates to search through.
     * @param fromTimestamp The inclusive start timestamp of the range to search for.
     * @param toTimestamp The exclusive end timestamp of the range to search for.
     * @return startIndex The start index of the yield rates that overlap with the given timestamp range.
     * @return endIndex The end index of the yield rates that overlap with the given timestamp range.
     */
    function _inRangeYieldRates(
        YieldRate[] memory yieldRates,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) internal pure returns (uint256 startIndex, uint256 endIndex) {
        uint256 length = yieldRates.length;

        if (length == 0) {
            revert YieldStreamer_YieldRateArrayIsEmpty();
        }

        if (fromTimestamp >= toTimestamp) {
            revert YieldStreamer_TimeRangeIsInvalid();
        }

        uint256 rateTimestamp;
        uint256 i = length;
        endIndex = length; // Indicates unset value.

        /**
         * NOTE:
         * There are common rules we assume to be followed for the rates array:
         * 1. The first rate in the rates array must always have the effective day equal to 0.
         * 2. The rates array is sorted by the effective day in ascending.
         * 3. The effective day in each rate is always greater than the previous rate's effective day.
         * The assumption that mentioned rules are followed is crucial for the logic below.
         */

        /**
         * NOTE:
         * For optimization purposes, we iterate from the end to the beginning of the rates array.
         * This allows us to not iterate through the entire array when we found the start index.
         */

        /**
         * The loop iterates through the rates array to find:
         * 1. `endIndex`: The last rate that starts before `toTimestamp`;
         * 2. `startIndex`: The first rate that starts before or at `fromTimestamp`.
         */
        do {
            // First iteration starts from length-1.
            i--;

            // Convert rate's effective day to timestamp.
            // Cast `effectiveDay` to `uint256` to avoid underflow.
            rateTimestamp = uint256(yieldRates[i].effectiveDay) * 1 days;

            // Skip rates that start after or at `toTimestamp`.
            // These rates are too late to be relevant for our time range.
            if (rateTimestamp >= toTimestamp) {
                continue;
            }

            // If we haven't found an `endIndex` yet and we found a rate
            // that starts before `toTimestamp`, this is our `endIndex`.
            if (endIndex == length) {
                endIndex = i;
            }

            // If we find a rate that starts before or at `fromTimestamp`:
            // 1. This becomes our `startIndex`;
            // 2. We can break the loop since earlier rates won't be relevant.
            if (rateTimestamp <= fromTimestamp) {
                startIndex = i;
                break;
            }
        } while (i > 0);

        return (startIndex, endIndex);
    }

    /**
     * @dev Aggregates yield results from multiple periods.
     *
     * @param yieldResults The array of yield results to aggregate.
     * @return accruedYield The aggregated accrued yield.
     * @return streamYield The aggregated stream yield.
     */
    function _aggregateYield(
        YieldResult[] memory yieldResults
    ) internal pure returns (uint256 accruedYield, uint256 streamYield) {
        uint256 length = yieldResults.length;

        if (length == 0) {
            return (0, 0);
        }

        // Initialize `accruedYield` from the first item of the yield results.
        accruedYield = yieldResults[0].firstDayPartialYield + yieldResults[0].fullDaysYield;

        // If there's only one yield result, set `streamYield` to the `lastDayPartialYield` of the first period.
        if (length == 1) {
            streamYield = yieldResults[0].lastDayPartialYield;
            return (accruedYield, streamYield);
        }

        // If there's more than one yield result, add the `lastDayPartialYield` of the first period to `accruedYield`.
        accruedYield += yieldResults[0].lastDayPartialYield;

        // Aggregate the yields from the remaining periods by summing up the `firstDayPartialYield`, `fullDaysYield`,
        // and `lastDayPartialYield` items.
        for (uint256 i = 1; i < length; i++) {
            YieldResult memory result = yieldResults[i];
            accruedYield += result.firstDayPartialYield + result.fullDaysYield + result.lastDayPartialYield;
        }

        // The `streamYield` is the `lastDayPartialYield` of the last period, so we remove it from `accruedYield`.
        accruedYield -= yieldResults[length - 1].lastDayPartialYield;

        // Set `streamYield` to the `lastDayPartialYield` of the last period.
        streamYield = yieldResults[length - 1].lastDayPartialYield;

        // Return the aggregated yield results.
        return (accruedYield, streamYield);
    }

    // ------------------ Timestamp ------------------------------- //

    /**
     * @dev Calculates the effective timestamp of the beginning of the day.
     *
     * @param timestamp The timestamp to calculate from.
     * @return The resulting effective timestamp.
     */
    function _effectiveTimestamp(uint256 timestamp) internal pure returns (uint256) {
        return (timestamp / 1 days) * 1 days;
    }

    /**
     * @dev Returns the current block timestamp after subtracting `NEGATIVE_TIME_SHIFT`.
     * The block timestamp shift is applied to align the yield calculation periods.
     *
     * @return The resulting adjusted timestamp.
     */
    function _blockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp - NEGATIVE_TIME_SHIFT;
    }

    // ------------------ Utility --------------------------------- //

    /**
     * @dev Truncates a portion of the yield rates array based on start and end indices.
     *
     * @param startIndex The start index of the truncation.
     * @param endIndex The end index of the truncation.
     * @param yieldRates The array of yield rates to truncate.
     * @return truncatedRates The truncated array of yield rates.
     */
    function _truncateArray(
        uint256 startIndex,
        uint256 endIndex,
        YieldRate[] memory yieldRates
    ) internal pure returns (YieldRate[] memory truncatedRates) {
        truncatedRates = new YieldRate[](endIndex - startIndex + 1);
        for (uint256 i = startIndex; i <= endIndex; ++i) {
            truncatedRates[i - startIndex] = yieldRates[i];
        }
    }

    /**
     * @dev Calculates the fee for a given amount based on the fee rate.
     *
     * @param amount The amount to calculate the fee for.
     * @return feeAmount The calculated fee amount.
     */
    function _calculateFee(uint256 amount) internal pure returns (uint256 feeAmount) {
        feeAmount = (amount * FEE_RATE) / RATE_FACTOR;
    }

    /**
     * @dev Rounds down an amount to the nearest multiple of `ROUND_FACTOR`.
     *
     * @param amount The amount to round down.
     * @return roundedAmount The rounded down amount.
     */
    function _roundDown(uint256 amount) internal pure returns (uint256 roundedAmount) {
        roundedAmount = (amount / ROUND_FACTOR) * ROUND_FACTOR;
    }

    /**
     * @dev Rounds up an amount to the nearest multiple of `ROUND_FACTOR`.
     *
     * @param amount The amount to round up.
     * @return roundedAmount The rounded up amount.
     */
    function _roundUp(uint256 amount) internal pure returns (uint256 roundedAmount) {
        roundedAmount = _roundDown(amount);
        if (roundedAmount < amount) {
            roundedAmount += ROUND_FACTOR;
        }
    }

    /**
     * @dev Maps an `AccruePreview` struct to a `ClaimPreview` struct.
     *
     * @param accruePreview The `AccruePreview` struct to map from.
     * @return claimPreview The resulting `ClaimPreview` struct.
     */
    function _map(AccruePreview memory accruePreview) internal pure returns (ClaimPreview memory claimPreview) {
        uint256 totalYield = accruePreview.accruedYieldAfter + accruePreview.streamYieldAfter;
        claimPreview.yield = _roundDown(totalYield);
        claimPreview.fee = 0; // Fees are not supported yet.
        claimPreview.timestamp = accruePreview.toTimestamp;
        claimPreview.balance = accruePreview.balance;

        uint256 lastRateIndex = accruePreview.rates.length - 1;
        uint256 lastRateLength = accruePreview.rates[lastRateIndex].tiers.length;
        uint256[] memory rates = new uint256[](lastRateLength);
        uint256[] memory caps = new uint256[](lastRateLength);
        for (uint256 i = 0; i < lastRateLength; ++i) {
            rates[i] = accruePreview.rates[lastRateIndex].tiers[i].rate;
            caps[i] = accruePreview.rates[lastRateIndex].tiers[i].cap;
        }

        claimPreview.rates = rates;
        claimPreview.caps = caps;
    }

    // ------------------ Overrides ------------------------------- //

    /**
     * @dev Initializes a single account.
     * This function should be overridden by inheriting contracts to provide specific initialization logic.
     *
     * @param account The account to initialize.
     */
    function _initializeSingleAccount(address account) internal virtual;
}
