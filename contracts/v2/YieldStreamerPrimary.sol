// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "hardhat/console.sol";

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

        YieldRate[] storage rates = $.yieldRates[$.groups[account].id];

        _accrueYield(account, state, rates);
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
                YieldRate[] storage rates = $.yieldRates[$.groups[account].id];
                _accrueYield(account, state, rates);
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
                YieldRate[] storage rates = $.yieldRates[$.groups[account].id];
                _accrueYield(account, state, rates);
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
        YieldRate[] storage rates = $.yieldRates[$.groups[account].id];
        ClaimPreview memory preview = _map(_getAccruePreview(state, rates, currentTimestamp));
        preview.timestamp = currentTimestamp;
        return preview;
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
        YieldRate[] storage rates = $.yieldRates[$.groups[account].id];
        return _getAccruePreview(state, rates, currentTimestamp);
    }

    /**
     * @dev Generates an accrue preview for a given account based on its current yield state and yield rates.
     * Provides detailed information about the yield accrual without modifying the state.
     *
     * @param state The current yield state of the account.
     * @param rates The yield rates to use for the calculation.
     * @return An `AccruePreview` struct containing details of the accrued yield.
     */
    function _getAccruePreview(
        YieldState storage state,
        YieldRate[] storage rates,
        uint256 currentTimestamp
    ) private view returns (AccruePreview memory) {
        AccruePreview memory preview;

        preview.balance = state.lastUpdateBalance;
        preview.streamYieldBefore = state.streamYield;
        preview.accruedYieldBefore = state.accruedYield;
        preview.fromTimestamp = state.lastUpdateTimestamp;
        preview.toTimestamp = currentTimestamp;

        (uint256 rateStartIndex, uint256 rateEndIndex) = _inRangeYieldRates(
            rates,
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

        YieldResult[] memory calculateResults = _calculateYield(calculateParams, rates);
        (preview.accruedYieldAfter, preview.streamYieldAfter) = _aggregateYield(calculateResults);
        preview.accruedYieldAfter += preview.accruedYieldBefore;

        preview.rates = _truncateArray(rateStartIndex, rateEndIndex, rates);
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
     * Updates the accrued yield and stream yield based on the elapsed time and yield rates.
     *
     * @param account The account to accrue yield for.
     */
    function _accrueYield(address account) internal virtual {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldState storage state = $.yieldStates[account];
        YieldRate[] storage rates = $.yieldRates[$.groups[account].id];
        _accrueYield(account, state, rates);
    }

    /**
     * @dev Accrues the yield for a given account and period.
     * Calculates the new accrued yield and stream yield based on the time elapsed and updates the yield state.
     *
     * @param account The account to accrue the yield for.
     * @param state The current yield state of the account.
     * @param rates The yield rates to use for the calculation.
     */
    function _accrueYield(
        address account, // Tools: this comment prevents Prettier from formatting into a single line.
        YieldState storage state,
        YieldRate[] storage rates
    ) private {
        uint256 currentTimestamp = _blockTimestamp();
        AccruePreview memory preview = _getAccruePreview(state, rates, currentTimestamp);

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
     * Handles multiple yield rate periods that may occur within the time range.
     *
     * @param params The parameters for the yield calculation, including timestamps and initial values.
     * @param rates The array of yield rates to use for the calculation.
     * @return An array of `YieldResult` structs containing yield calculations for sub-periods.
     */
    function _calculateYield(
        CalculateYieldParams memory params,
        YieldRate[] storage rates // Tools: this comment prevents Prettier from formatting into a single line.
    ) private view returns (YieldResult[] memory) {
        YieldResult[] memory results;
        uint256 ratePeriods = params.rateEndIndex - params.rateStartIndex + 1;
        uint256 localFromTimestamp = params.fromTimestamp;
        uint256 localToTimestamp = params.toTimestamp;

        // TODO: Double-check inclusion of the last second!!

        // bool _debug = false;

        // if (_debug) {
        //     console.log("");
        //     console.log("_calculateYield | START");

        //     console.log("");
        //     console.log("_calculateYield | Input params:");
        //     console.log("_calculateYield | - initialBalance: %s", params.initialBalance);
        //     console.log("_calculateYield | - initialAccruedYield: %s", params.initialAccruedYield);
        //     console.log("_calculateYield | - initialStreamYield: %s", params.initialStreamYield);
        //     console.log(
        //         "_calculateYield | - fromTimestamp: %s (day: %s + seconds: %s)",
        //         localFromTimestamp,
        //         _effectiveDay(localFromTimestamp),
        //         _remainingSeconds(localFromTimestamp)
        //     );
        //     console.log(
        //         "_calculateYield | - toTimestamp: %s (day: %s + seconds: %s)",
        //         localToTimestamp,
        //         _effectiveDay(localToTimestamp),
        //         _remainingSeconds(localToTimestamp)
        //     );
        //     console.log("_calculateYield | - rates:");
        //     for (uint256 i = params.rateStartIndex; i <= params.rateEndIndex; i++) {
        //         console.log(
        //             "_calculateYield | -- [%s] day: %s, value: %s",
        //             i,
        //             rates[i].effectiveDay,
        //             rates[i].value
        //         );
        //     }
        // }

        if (ratePeriods == 0) {
            /**
             * Scenario 0
             * If there are no yield rate periods in the range, we return an empty array.
             */

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Scenario 0: No yield rates in range");
            // }

            results = new YieldResult[](0);
        } else if (ratePeriods == 1) {
            /**
             * Scenario 1
             * If there is only one yield rate period in the range, we calculate the yield for the entire range
             * using this yield rate.
             */

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Scenario 1: One yield rate in range");

            //     console.log("");
            //     console.log("_calculateYield | Calculating yield:");
            //     console.log("_calculateYield | - yieldRate: %s", rates[params.rateStartIndex].value);
            //     console.log(
            //         "_calculateYield | - fromTimestamp: %s (day: %s + seconds: %s)",
            //         localFromTimestamp,
            //         _effectiveDay(localFromTimestamp),
            //         _remainingSeconds(localFromTimestamp)
            //     );
            //     console.log(
            //         "_calculateYield | - toTimestamp: %s (day: %s + seconds: %s)",
            //         localToTimestamp,
            //         _effectiveDay(localToTimestamp),
            //         _remainingSeconds(localToTimestamp)
            //     );
            // }

            results = new YieldResult[](1);
            results[0] = _compoundYield(
                CompoundYieldParams(
                    localFromTimestamp,
                    localToTimestamp,
                    rates[params.rateStartIndex].tiers,
                    params.initialBalance + params.initialAccruedYield,
                    params.initialStreamYield
                )
            );

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Result:");
            //     console.log("_calculateYield | - firstDayPartialYield: %s", result[0].firstDayPartialYield);
            //     console.log("_calculateYield | - fullDaysYield: %s", result[0].fullDaysYield);
            //     console.log("_calculateYield | - lastDayPartialYield: %s", result[0].lastDayPartialYield);
            // }
        } else if (ratePeriods == 2) {
            /**
             * Scenario 2
             * If there are two yield rate periods in the range, we:
             * 1. Use the first yield rate to calculate the yield from `fromTimestamp` to the start of the second yield rate period.
             * 2. Use the second yield rate to calculate the yield from the start of the second yield rate period to `toTimestamp`.
             */

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Scenario 2: Two yield rates in range");
            // }

            results = new YieldResult[](2);
            localFromTimestamp = params.fromTimestamp;
            localToTimestamp = rates[params.rateStartIndex + 1].effectiveDay * 1 days;

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Calculating yield for first period:");
            //     console.log("_calculateYield | - yieldRate: %s", rates[params.rateStartIndex].value);
            //     console.log(
            //         " _calculateYield | - fromTimestamp: %s (day: %s + seconds: %s)",
            //         localFromTimestamp,
            //         _effectiveDay(localFromTimestamp),
            //         _remainingSeconds(localFromTimestamp)
            //     );
            //     console.log(
            //         " _calculateYield | - localToTimestamp: %s (day: %s + seconds: %s)",
            //         localToTimestamp,
            //         _effectiveDay(localToTimestamp),
            //         _remainingSeconds(localToTimestamp)
            //     );
            // }

            results[0] = _compoundYield(
                CompoundYieldParams(
                    localFromTimestamp,
                    localToTimestamp,
                    rates[params.rateStartIndex].tiers,
                    params.initialBalance + params.initialAccruedYield,
                    params.initialStreamYield
                )
            );

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Result:");
            //     console.log("_calculateYield | - firstDayPartialYield: %s", result[0].firstDayPartialYield);
            //     console.log("_calculateYield | - fullDaysYield: %s", result[0].fullDaysYield);
            //     console.log("_calculateYield | - lastDayPartialYield: %s", result[0].lastDayPartialYield);
            // }

            localFromTimestamp = localToTimestamp;
            localToTimestamp = params.toTimestamp;

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Calculating yield for second period:");
            //     console.log(
            //         " _calculateYield | - yieldRate: %s",
            //         rates[params.rateStartIndex + 1].value
            //     );
            //     console.log(
            //         " _calculateYield | - fromTimestamp: %s (day: %s + seconds: %s)",
            //         localFromTimestamp,
            //         _effectiveDay(localFromTimestamp),
            //         _remainingSeconds(localFromTimestamp)
            //     );
            //     console.log(
            //         " _calculateYield | - toTimestamp: %s (day: %s + seconds: %s)",
            //         localToTimestamp,
            //         _effectiveDay(localToTimestamp),
            //         _remainingSeconds(localToTimestamp)
            //     );
            // }

            results[1] = _compoundYield(
                CompoundYieldParams(
                    localFromTimestamp,
                    localToTimestamp,
                    rates[params.rateStartIndex + 1].tiers,
                    params.initialBalance +
                        params.initialAccruedYield +
                        results[0].firstDayPartialYield +
                        results[0].fullDaysYield +
                        results[0].lastDayPartialYield,
                    0
                )
            );

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Result:");
            //     console.log("_calculateYield | - firstDayPartialYield: %s", result[1].firstDayPartialYield);
            //     console.log("_calculateYield | - fullDaysYield: %s", result[1].fullDaysYield);
            //     console.log("_calculateYield | - lastDayPartialYield: %s", result[1].lastDayPartialYield);
            // }
        } else {
            /**
             * Scenario 3
             * If there are more than two yield rate periods in the range, we:
             * 1. Use the first yield rate to calculate the yield from `fromTimestamp` to the start of the second yield rate period.
             * 2. Use the second yield rate to calculate the yield from the start of the second yield rate period to the start of the third yield rate period.
             * 3. Repeat this process for each subsequent yield rate period until the last yield rate period.
             * 4. Use the last yield rate to calculate the yield from the start of the last yield rate period to `toTimestamp`.
             */

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Scenario 3: More than two yield rates in range");
            // }

            uint256 currentBalance = params.initialBalance + params.initialAccruedYield;
            results = new YieldResult[](ratePeriods);
            localFromTimestamp = params.fromTimestamp;
            localToTimestamp = uint256(rates[params.rateStartIndex + 1].effectiveDay) * 1 days;

            // Calculate yield for the first period

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Calculating yield for first period:");
            //     console.log("_calculateYield | - yieldRate: %s", rates[params.rateStartIndex].value);
            //     console.log(
            //         " _calculateYield | - fromTimestamp: %s (day: %s + seconds: %s)",
            //         localFromTimestamp,
            //         _effectiveDay(localFromTimestamp),
            //         _remainingSeconds(localFromTimestamp)
            //     );
            //     console.log(
            //         " _calculateYield | - localToTimestamp: %s (day: %s + seconds: %s)",
            //         localToTimestamp,
            //         _effectiveDay(localToTimestamp),
            //         _remainingSeconds(localToTimestamp)
            //     );
            // }

            results[0] = _compoundYield(
                CompoundYieldParams(
                    localFromTimestamp,
                    localToTimestamp,
                    rates[params.rateStartIndex].tiers,
                    currentBalance,
                    params.initialStreamYield
                )
            );

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | First period result:");
            //     console.log("_calculateYield | - firstDayPartialYield: %s", result[0].firstDayPartialYield);
            //     console.log("_calculateYield | - fullDaysYield: %s", result[0].fullDaysYield);
            //     console.log("_calculateYield | - lastDayPartialYield: %s", result[0].lastDayPartialYield);
            // }

            currentBalance +=
                results[0].firstDayPartialYield +
                results[0].fullDaysYield +
                results[0].lastDayPartialYield;

            // Calculate yield for the intermediate periods

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Calculating yield for full %s periods:", ratePeriods - 2);
            // }

            for (uint256 i = params.rateStartIndex + 1; i < params.rateEndIndex; i++) {
                localFromTimestamp = uint256(rates[i].effectiveDay) * 1 days;
                localToTimestamp = uint256(rates[i + 1].effectiveDay) * 1 days;

                // if (_debug) {
                //     console.log("");
                //     console.log("_calculateYield | Period #%s:", i);
                //     console.log("_calculateYield | - yieldRate: %s", rates[i].value);
                //     console.log(
                //         "_calculateYield | - fromTimestamp: %s (day: %s + seconds: %s)",
                //         localFromTimestamp,
                //         _effectiveDay(localFromTimestamp),
                //         _remainingSeconds(localFromTimestamp)
                //     );
                //     console.log(
                //         "_calculateYield | - toTimestamp: %s (day: %s + seconds: %s)",
                //         localToTimestamp,
                //         _effectiveDay(localToTimestamp),
                //         _remainingSeconds(localToTimestamp)
                //     );
                // }

                results[i - params.rateStartIndex] = _compoundYield(
                    CompoundYieldParams(
                        localFromTimestamp, // Tools: this comment prevents Prettier from formatting into a single line.
                        localToTimestamp,
                        rates[i].tiers,
                        currentBalance,
                        0
                    )
                );

                // if (_debug) {
                //     console.log("");
                //     console.log("_calculateYield | Full period result: %s", i);
                //     console.log(
                //         "_calculateYield | - firstDayPartialYield: %s",
                //         result[i - params.rateStartIndex].firstDayPartialYield
                //     );
                //     console.log(
                //         "_calculateYield | - fullDaysYield: %s",
                //         result[i - params.rateStartIndex].fullDaysYield
                //     );
                //     console.log(
                //         "_calculateYield | - lastDayPartialYield: %s",
                //         result[i - params.rateStartIndex].lastDayPartialYield
                //     );
                // }

                currentBalance +=
                    results[i - params.rateStartIndex].firstDayPartialYield +
                    results[i - params.rateStartIndex].fullDaysYield +
                    results[i - params.rateStartIndex].lastDayPartialYield;
            }

            // Calculate yield for the last period

            localFromTimestamp = uint256(rates[params.rateStartIndex + ratePeriods - 1].effectiveDay) * 1 days;
            localToTimestamp = params.toTimestamp;

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | - Calculating yield for last period:");
            //     console.log(
            //         " _calculateYield | -- yieldRate: %s",
            //         rates[params.rateStartIndex + ratePeriods - 1].value
            //     );
            //     console.log(
            //         " _calculateYield | -- fromTimestamp: %s (day: %s + seconds: %s)",
            //         localFromTimestamp,
            //         _effectiveDay(localFromTimestamp),
            //         _remainingSeconds(localFromTimestamp)
            //     );
            //     console.log(
            //         " _calculateYield | -- toTimestamp: %s (day: %s + seconds: %s)",
            //         localToTimestamp,
            //         _effectiveDay(localToTimestamp),
            //         _remainingSeconds(localToTimestamp)
            //     );
            // }

            results[ratePeriods - 1] = _compoundYield(
                CompoundYieldParams(
                    localFromTimestamp,
                    localToTimestamp,
                    rates[params.rateStartIndex + ratePeriods - 1].tiers,
                    currentBalance,
                    0
                )
            );

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Last period result:");
            //     console.log("_calculateYield | - firstDayPartialYield: %s", result[ratePeriods - 1].firstDayPartialYield);
            //     console.log("_calculateYield | - fullDaysYield: %s", result[ratePeriods - 1].fullDaysYield);
            //     console.log("_calculateYield | - lastDayPartialYield: %s", result[ratePeriods - 1].lastDayPartialYield);
            // }
        }

        // if (_debug) {
        //     console.log("");
        //     console.log("_calculateYield | END");
        // }

        return results;
    }

    /**
     * @dev Calculates compounded yield over a specified time range using a single yield rate.
     * Handles partial and full days within the period, calculating yield accordingly.
     *
     * @param params The parameters for the yield calculation, including timestamps, yield rate, and balance.
     * @return A `YieldResult` struct containing the yield for first partial day, full days, and last partial day.
     */
    function _compoundYield(CompoundYieldParams memory params) private pure returns (YieldResult memory) {
        // bool _debug = false;

        // if (_debug) {
        //     console.log("");
        //     console.log("_compoundYield | START");

        //     console.log("");
        //     console.log("_compoundYield | Input params:");
        //     console.log("_compoundYield | - fromTimestamp: %s", fromTimestamp);
        //     console.log("_compoundYield | - toTimestamp: %s", toTimestamp);
        //     console.log("_compoundYield | - yieldRate: %s", yieldRate);
        //     console.log("_compoundYield | - balance: %s", balance);
        //     console.log("_compoundYield | - streamYield: %s", streamYield);
        // }

        YieldResult memory result;

        if (params.fromTimestamp > params.toTimestamp) {
            revert YieldStreamer_TimeRangeInvalid();
        }
        if (params.fromTimestamp == params.toTimestamp || params.balance == 0) {
            // if (_debug) {
            //     console.log("");
            //     console.log("_compoundYield | Case 0: Early exit");

            //     console.log("");
            //     console.log("_compoundYield | END");
            // }
            return YieldResult(0, 0, 0);
        }

        uint256 totalBalance = params.balance;
        uint256 nextDayStart = _nextDay(params.fromTimestamp);
        uint256 partDayYield = 0;

        if (nextDayStart >= params.toTimestamp) {
            /**
             * We are within the same day as the `fromTimestamp`.
             */

            partDayYield = _calculateTieredPartDayYield(
                totalBalance,
                params.tiers,
                params.toTimestamp - params.fromTimestamp
            );
            result.lastDayPartialYield = params.streamYield + partDayYield;

            // if (_debug) {
            //     console.log("");
            //     console.log("_compoundYield | Case 1: Within the same day");

            //     console.log("");
            //     console.log("_compoundYield | Calculating yield for elapsed time: %s", toTimestamp - fromTimestamp);
            //     console.log(
            //         "_compoundYield | - lastDayPartialYield = streamYield + partDayYield: %s + %s = %s",
            //         streamYield,
            //         partDayYield,
            //         result.lastDayPartialYield
            //     );
            // }
        } else {
            /**
             * We are spanning multiple days.
             */

            // if (_debug) {
            //     console.log("");
            //     console.log("_compoundYield | Case 2: Spanning multiple days");
            // }

            /**
             * 1. Calculate yield for the first partial day.
             */

            uint256 firstDaySeconds = nextDayStart - params.fromTimestamp;

            if (firstDaySeconds != 1 days) {
                partDayYield = _calculateTieredPartDayYield(totalBalance, params.tiers, firstDaySeconds);
                result.firstDayPartialYield = params.streamYield + partDayYield;

                // if (_debug) {
                //     console.log("");
                //     console.log(
                //         "_compoundYield | Calculating yield for the first partial day remaining seconds %s",
                //         firstDaySeconds
                //     );
                //     console.log(
                //         "_compoundYield | - firstDayPartialYield = streamYield + partDayYield: %s + %s = %s",
                //         streamYield,
                //         partDayYield,
                //         result.firstDayPartialYield
                //     );
                // }

                totalBalance += result.firstDayPartialYield;
                params.fromTimestamp = nextDayStart;
            }

            /**
             * 2. Calculate yield for each full day.
             */

            uint256 fullDaysCount = (params.toTimestamp - params.fromTimestamp) / 1 days;

            if (fullDaysCount > 0) {
                // if (_debug) {
                //     console.log("");
                //     console.log("_compoundYield | Calculating yield for full days count: %s", fullDaysCount);
                // }

                for (uint256 i = 0; i < fullDaysCount; i++) {
                    uint256 dailyYield = _calculateTieredFullDayYield(
                        totalBalance + result.fullDaysYield,
                        params.tiers
                    );
                    result.fullDaysYield += dailyYield;

                    // if (_debug) {
                    //     console.log("_compoundYield | - [%s] full day yield: %s", i, dailyYield);
                    // }
                }

                totalBalance += result.fullDaysYield;
                params.fromTimestamp += fullDaysCount * 1 days;
            }

            /**
             * 3. Calculate yield for the last partial day.
             */

            if (params.fromTimestamp < params.toTimestamp) {
                // if (_debug) {
                //     console.log("");
                //     console.log("_compoundYield | Calculating yield for the last partial day");
                // }

                uint256 lastDaySeconds = params.toTimestamp - params.fromTimestamp;
                result.lastDayPartialYield = _calculateTieredPartDayYield(totalBalance, params.tiers, lastDaySeconds);

                // if (_debug) {
                //     console.log("_compoundYield | - last day remaining seconds: %s", lastDaySeconds);
                //     console.log("_compoundYield | - last day partial yield: %s", result.lastDayPartialYield);
                // }
            }
        }

        // if (_debug) {
        //     console.log("");
        //     console.log("_compoundYield | Final result:");
        //     console.log("_compoundYield | - firstDayPartialYield: %s", result.firstDayPartialYield);
        //     console.log("_compoundYield | - fullDaysYield: %s", result.fullDaysYield);
        //     console.log("_compoundYield | - lastDayPartialYield: %s", result.lastDayPartialYield);

        //     console.log("");
        //     console.log("_compoundYield | END");
        // }

        return result;
    }

    /**
     * @dev Calculates the yield for a partial day.
     *
     * @param amount The amount to calculate the yield for.
     * @param tiers The yield tiers to apply during the calculation period.
     * @param elapsedSeconds The elapsed seconds within the day.
     * @return The yield accrued during the partial day.
     */
    function _calculateTieredPartDayYield(
        uint256 amount,
        RateTier[] memory tiers,
        uint256 elapsedSeconds
    ) internal pure returns (uint256) {
        uint256 remainingAmount = amount;
        uint256 totalYield = 0;
        uint256 i = 0;
        uint256 cappedAmount;
        RateTier memory tier;

        do {
            if (remainingAmount == 0) {
                break;
            }

            tier = tiers[i];

            if (tier.cap == 0) {
                cappedAmount = remainingAmount;
            } else if (remainingAmount > tier.cap) {
                cappedAmount = tier.cap;
            } else {
                cappedAmount = remainingAmount;
            }

            totalYield += _calculateSimplePartDayYield(cappedAmount, tier.rate, elapsedSeconds);
            remainingAmount -= cappedAmount;
            i++;
        } while (i < tiers.length);

        return totalYield;
    }

    /**
     * @dev Calculates the yield for a full day.
     *
     * @param amount The amount to calculate the yield for.
     * @param tiers The yield tiers to apply during the calculation period.
     * @return The yield accrued during the full day.
     */
    function _calculateTieredFullDayYield(uint256 amount, RateTier[] memory tiers) internal pure returns (uint256) {
        uint256 remainingAmount = amount;
        uint256 totalYield = 0;
        uint256 i = 0;
        uint256 cappedAmount;
        RateTier memory tier;

        do {
            if (remainingAmount == 0) {
                break;
            }

            tier = tiers[i];

            if (tier.cap == 0) {
                cappedAmount = remainingAmount;
            } else if (remainingAmount > tier.cap) {
                cappedAmount = tier.cap;
            } else {
                cappedAmount = remainingAmount;
            }

            totalYield += _calculateSimpleFullDayYield(cappedAmount, tier.rate);
            remainingAmount -= cappedAmount;
            i++;
        } while (i < tiers.length);

        return totalYield;
    }

    function _calculateSimplePartDayYield(
        uint256 amount,
        uint256 rate,
        uint256 elapsedSeconds
    ) internal pure returns (uint256) {
        return (amount * rate * elapsedSeconds) / (1 days * RATE_FACTOR);
    }

    function _calculateSimpleFullDayYield(uint256 amount, uint256 rate) internal pure returns (uint256) {
        return (amount * rate) / RATE_FACTOR;
    }

    // Tested
    /**
     * @dev Finds the yield rates that overlap with the given timestamp range.
     *
     * @param rates The array of yield rates to search through.
     * @param fromTimestamp The start timestamp (inclusive).
     * @param toTimestamp The end timestamp (exclusive).
     * @return The start and end index of the yield rates.
     */
    function _inRangeYieldRates(
        YieldRate[] storage rates,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) internal view returns (uint256, uint256) {
        uint256 length = rates.length;

        if (length == 0) {
            revert YieldStreamer_YieldRateArrayIsEmpty();
        }

        if (fromTimestamp >= toTimestamp) {
            revert YieldStreamer_TimeRangeIsInvalid();
        }

        uint256 startIndex;
        uint256 endIndex = length; // Indicates unset.
        uint256 rateTimestamp;
        uint256 i = length;

        /**
         * Notes:
         * There are common rules for the rates array:
         * 1. The first rate in the rates array must always have the effective day equal to 0.
         * 2. The rates array is sorted by the effective day in ascending.
         * 3. The effective day in each rate is always greater than the previous rate's effective day.
         * The assumption that mentioned rules are followed is crucial for the logic below.
         */

        do {
            i--;

            rateTimestamp = uint256(rates[i].effectiveDay) * 1 days;

            if (rateTimestamp >= toTimestamp) {
                continue;
            }

            if (endIndex == length) {
                endIndex = i;
            }

            if (rateTimestamp <= fromTimestamp) {
                startIndex = i;
                break;
            }
        } while (i > 0);

        return (startIndex, endIndex);
    }

    // Tested
    /**
     * @dev Aggregates the yield results from multiple periods.
     *
     * @param yieldResults The array of yield results to aggregate.
     * @return The final/updated accrued yield and stream yield.
     */
    function _aggregateYield(YieldResult[] memory yieldResults) internal pure returns (uint256, uint256) {
        uint256 length = yieldResults.length;
        uint256 accruedYield;
        uint256 streamYield;

        if (length == 0) {
            return (0, 0);
        }

        // Initialize accruedYield with the first yield result's components
        accruedYield = yieldResults[0].firstDayPartialYield + yieldResults[0].fullDaysYield;

        // For a single yield result, set streamYield to the lastDayPartialYield of the first (and only) period
        if (length == 1) {
            streamYield = yieldResults[0].lastDayPartialYield;
            return (accruedYield, streamYield);
        }

        // If there's more than one yield result, include the lastDayPartialYield of the first period to accruedYield
        accruedYield += yieldResults[0].lastDayPartialYield;

        // Accumulate yields from the remaining periods (if any)
        for (uint256 i = 1; i < length; i++) {
            YieldResult memory result = yieldResults[i];
            accruedYield += result.firstDayPartialYield + result.fullDaysYield + result.lastDayPartialYield;
        }

        // The streamYield is always the last lastDayPartialYield, so we remove it from accruedYield
        accruedYield -= yieldResults[length - 1].lastDayPartialYield;
        streamYield = yieldResults[length - 1].lastDayPartialYield;

        return (accruedYield, streamYield);
    }

    // ------------------ Timestamp ------------------------------- //

    // Tested
    /**
     * @dev Calculates a timestamp for the beginning of the next day.
     *
     * @param timestamp The timestamp to calculate from.
     * @return The timestamp of the next day.
     */
    function _nextDay(uint256 timestamp) internal pure returns (uint256) {
        return timestamp - (timestamp % 1 days) + 1 days;
    }

    // Tested
    /**
     * @dev Calculates the number of the effective day from a timestamp.
     *
     * @param timestamp The timestamp to calculate from.
     * @return The number of the effective day.
     */
    function _effectiveDay(uint256 timestamp) internal pure returns (uint256) {
        return timestamp / 1 days;
    }

    // Tested
    /**
     * @dev Calculates the remaining seconds before the next day.
     *
     * @param timestamp The timestamp to calculate from.
     * @return The remaining seconds.
     */
    function _remainingSeconds(uint256 timestamp) internal pure returns (uint256) {
        return timestamp % 1 days;
    }

    // Tested
    /**
     * @dev Calculates the timestamp of the beginning of the day.
     *
     * @param timestamp The timestamp to calculate from.
     * @return The timestamp of the day.
     */
    function _effectiveTimestamp(uint256 timestamp) internal pure returns (uint256) {
        return (timestamp / 1 days) * 1 days;
    }

    /**
     * @dev Returns the current block timestamp, adjusted by the negative time shift.
     * The negative time shift is applied to align the yield calculation periods.
     *
     * @return The adjusted current block timestamp.
     */
    function _blockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp - NEGATIVE_TIME_SHIFT;
    }

    // ------------------ Utility --------------------------------- //

    // Tested
    /**
     * @dev Truncates a portion of the yield rates array based on start and end indices.
     *
     * @param startIndex The start index of the truncation.
     * @param endIndex The end index of the truncation.
     * @param rates The array of yield rates.
     * @return The truncated array of yield rates.
     */
    function _truncateArray(
        uint256 startIndex,
        uint256 endIndex,
        YieldRate[] storage rates
    ) internal view returns (YieldRate[] memory) {
        YieldRate[] memory result = new YieldRate[](endIndex - startIndex + 1);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            result[i - startIndex] = rates[i];
        }
        return result;
    }

    /**
     * @dev Calculates the fee for a given amount based on the fee rate.
     *
     * @param amount The amount to calculate the fee for.
     * @return The calculated fee amount.
     */
    function _calculateFee(uint256 amount) private pure returns (uint256) {
        return (amount * FEE_RATE) / RATE_FACTOR;
    }

    // Tested
    /**
     * @dev Rounds down an amount to the nearest multiple of `ROUND_FACTOR`.
     *
     * @param amount The amount to round down.
     * @return The rounded down amount.
     */
    function _roundDown(uint256 amount) internal pure returns (uint256) {
        return (amount / ROUND_FACTOR) * ROUND_FACTOR;
    }

    // Tested
    /**
     * @dev Rounds up an amount to the nearest multiple of `ROUND_FACTOR`.
     *
     * @param amount The amount to round up.
     * @return The rounded up amount.
     */
    function _roundUp(uint256 amount) internal pure returns (uint256) {
        uint256 roundedAmount = _roundDown(amount);

        if (roundedAmount < amount) {
            roundedAmount += ROUND_FACTOR;
        }

        return roundedAmount;
    }

    // Tested
    /**
     * @dev Maps an `AccruePreview` to a `ClaimPreview`.
     *
     * @param accrue The accrue preview to map from.
     * @return The resulting claim preview.
     */
    function _map(AccruePreview memory accrue) internal pure returns (ClaimPreview memory) {
        ClaimPreview memory claim;

        uint256 totalYield = accrue.accruedYieldAfter + accrue.streamYieldAfter;
        claim.yield = _roundDown(totalYield);
        claim.fee = 0;
        claim.timestamp = 0;
        claim.balance = accrue.balance;

        uint256 lastRateIndex = accrue.rates.length - 1;
        uint256 lastRateLength = accrue.rates[lastRateIndex].tiers.length;
        uint256[] memory rates = new uint256[](lastRateLength);
        uint256[] memory caps = new uint256[](lastRateLength);
        for (uint256 i = 0; i < lastRateLength; i++) {
            rates[i] = accrue.rates[lastRateIndex].tiers[i].rate;
            caps[i] = accrue.rates[lastRateIndex].tiers[i].cap;
        }
        claim.rates = rates;
        claim.caps = caps;

        return claim;
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
