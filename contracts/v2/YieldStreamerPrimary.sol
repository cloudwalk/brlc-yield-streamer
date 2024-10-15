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

/**
 * @title YieldStreamerPrimary contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev The contract that responsible for the yield calculation and distribution.
 */
abstract contract YieldStreamerPrimary is
    YieldStreamerStorage,
    IYieldStreamerPrimary_Errors,
    IYieldStreamerPrimary_Events,
    IERC20Hook
{
    // -------------------- Libs ---------------------------------- //

    using SafeCast for uint256;
    using Bitwise for uint8;

    // -------------------- Structs ------------------------------- //

    /**
     * @dev Structure that contains the parameters for calculating the yield.
     *
     * Fields:
     *  - fromTimestamp: -- The timestamp of the period start.
     *  - toTimestamp: ---- The timestamp of the period end.
     *  - yieldRate: ------ The yield rate.
     *  - balance: -------- The balance.
     *  - streamYield: ---- The stream yield.
     */
    struct CompoundYieldParams {
        uint256 fromTimestamp;
        uint256 toTimestamp;
        uint256 yieldRate;
        uint256 balance;
        uint256 streamYield;
    }

    /**
     * @dev Structure that contains the parameters for calculating the yield.
     *
     * Fields:
     *  - fromTimestamp: -------- The timestamp of the period start.
     *  - toTimestamp: ---------- The timestamp of the period end.
     *  - rateStartIndex: ------- The start index of the yield rates.
     *  - rateEndIndex: --------- The end index of the yield rates.
     *  - initialBalance: ------- The initial balance at the period start.
     *  - initialStreamYield: --- The initial stream yield at the period start.
     *  - initialAccruedYield: -- The initial accrued yield at the period start.
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
     * @dev Modifier to ensure the caller is the underlying token.
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
        // Do nothing
    }

    /**
     * @inheritdoc IERC20Hook
     */
    function afterTokenTransfer(address from, address to, uint256 amount) external onlyToken {
        if (from != address(0)) {
            // Saves gas during minting
            _decreaseTokenBalance(from, amount);
        }
        if (to != address(0)) {
            // Saves gas during burning
            _increaseTokenBalance(to, amount);
        }
    }

    // -------------------- Functions ------------------------------ //

    /**
     * @dev Claims the yield for a given account.
     * @param account The account to claim the yield for.
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
     * @dev Increases the token balance for a given account.
     * @param account The account to increase the token balance for.
     * @param amount The amount of token to increase.
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
     * @dev Decreases the token balance for a given account.
     * @param account The account to decrease the token balance for.
     * @param amount The amount of token to decrease.
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
     * @dev Tries to initialize a yield state for a given account.
     * @param account The account to try to initialize.
     * @return True if the account was initialized, false otherwise.
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
     * @dev Transfers the yield for a given account.
     * @param account The account to transfer the yield for.
     * @param amount The amount of yield to transfer.
     * @param state The current state of the yield.
     * @param feeReceiver The address to receive the fee.
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
     * @dev Gets the yield state for a given account.
     * @param account The account to get the yield state for.
     * @return The yield state.
     */
    function _getYieldState(address account) internal view returns (YieldState memory) {
        return _yieldStreamerStorage().yieldStates[account];
    }

    /**
     * @dev Gets the claim preview for a given account.
     * @param account The account to get the claim preview for.
     * @return The claim preview.
     */
    function _getClaimPreview(address account) internal view returns (ClaimPreview memory) {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldState storage state = $.yieldStates[account];
        YieldRate[] storage rates = $.yieldRates[$.groups[account].id];
        ClaimPreview memory preview = _map(_getAccruePreview(state, rates));
        preview.timestamp = _blockTimestamp();
        return preview;
    }

    /**
     * @dev Gets the accrue preview for a given account.
     * @param account The account to get the accrue preview for.
     * @return The accrue preview.
     */
    function _getAccruePreview(address account) internal view returns (AccruePreview memory) {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldState storage state = $.yieldStates[account];
        YieldRate[] storage rates = $.yieldRates[$.groups[account].id];
        return _getAccruePreview(state, rates);
    }

    /**
     * @dev Gets the accrue preview for a given account.
     * @param state The current state of the yield.
     * @param rates The yield rates to use for the calculation.
     * @return The accrue preview.
     */
    function _getAccruePreview(
        YieldState storage state,
        YieldRate[] storage rates
    ) private view returns (AccruePreview memory) {
        AccruePreview memory preview;

        preview.balance = state.lastUpdateBalance;
        preview.streamYieldBefore = state.streamYield;
        preview.accruedYieldBefore = state.accruedYield;
        preview.fromTimestamp = state.lastUpdateTimestamp;
        preview.toTimestamp = _blockTimestamp();

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

    // ------------------ Yield calculation ----------------------- //

    /**
     * @dev Accrues the yield for a given account.
     * @param account The account to accrue the yield for.
     * @param state The current state of the yield.
     * @param rates The yield rates to use for the calculation.
     */
    function _accrueYield(
        address account, // Tools: this comment prevents Prettier from formatting into a single line.
        YieldState storage state,
        YieldRate[] storage rates
    ) private {
        AccruePreview memory preview = _getAccruePreview(state, rates);

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
     * @dev Accrues the yield for a given account and period.
     * @param account The account to accrue the yield for.
     */
    function _accrueYield(address account) internal virtual {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldState storage state = $.yieldStates[account];
        YieldRate[] storage rates = $.yieldRates[$.groups[account].id];
        _accrueYield(account, state, rates);
    }

    /**
     * @dev Calculates the yield for a given period.
     * @param params The parameters for the yield calculation.
     * @param rates The array of yield rates to use for the calculation.
     * @return The yield results for the given period.
     */
    function _calculateYield(
        CalculateYieldParams memory params,
        YieldRate[] storage rates // Format: prevent collapse
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
                    rates[params.rateStartIndex].value,
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
                    rates[params.rateStartIndex].value,
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
                    rates[params.rateStartIndex + 1].value,
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
                    rates[params.rateStartIndex].value,
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
                    CompoundYieldParams(localFromTimestamp, localToTimestamp, rates[i].value, currentBalance, 0)
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
                    rates[params.rateStartIndex + ratePeriods - 1].value,
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
     * @dev Compounds the yield for a given period.
     * @param params The parameters for the yield calculation.
     * @return The yield result for the given period.
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

            partDayYield = _calculatePartDayYield(
                totalBalance,
                params.yieldRate,
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
                partDayYield = _calculatePartDayYield(totalBalance, params.yieldRate, firstDaySeconds);
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
                    uint256 dailyYield = _calculateFullDayYield(totalBalance + result.fullDaysYield, params.yieldRate);
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
                result.lastDayPartialYield = _calculatePartDayYield(totalBalance, params.yieldRate, lastDaySeconds);

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
     * @param amount The amount to calculate the yield for.
     * @param yieldRate The yield rate.
     * @param elapsedSeconds The elapsed seconds.
     * @return The yield for the partial day.
     */
    function _calculatePartDayYield(
        uint256 amount,
        uint256 yieldRate,
        uint256 elapsedSeconds
    ) private pure returns (uint256) {
        return (amount * yieldRate * elapsedSeconds) / (1 days * RATE_FACTOR);
    }

    /**
     * @dev Calculates the yield for a full day.
     * @param amount The amount to calculate the yield for.
     * @param yieldRate The yield rate.
     * @return The yield for the full day.
     */
    function _calculateFullDayYield(
        uint256 amount, // Tools: this comment prevents Prettier from formatting into a single line.
        uint256 yieldRate
    ) private pure returns (uint256) {
        return (amount * yieldRate) / RATE_FACTOR;
    }

    /**
     * @dev Finds the yield rates within a given timestamp range.
     * @param rates The array of yield rates to search.
     * @param fromTimestamp The start timestamp.
     * @param toTimestamp The end timestamp.
     * @return The start and end index of the yield rates.
     */
    function _inRangeYieldRates(
        YieldRate[] storage rates,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) private view returns (uint256, uint256) {
        // bool _debug = false;

        // if (_debug) {
        //     console.log("");
        //     console.log("_inRangeYieldRates | START");
        //     console.log("_inRangeYieldRates | Getting yield rates from %s to %s", fromTimestamp, toTimestamp);

        //     console.log("");
        //     console.log("_inRangeYieldRates | Input yield rates:");
        //     for (uint256 k = 0; k < rates.length; k++) {
        //         console.log(
        //             "_inRangeYieldRates | - [%s] effectiveDay: %s, value: %s",
        //             k,
        //             rates[k].effectiveDay,
        //             rates[k].value
        //         );
        //     }

        //     console.log("");
        //     console.log("_inRangeYieldRates | Starting loop:");
        // }

        uint256 i = rates.length;
        uint256 startIndex = 0;
        uint256 endIndex = 0;

        do {
            i--;

            // if (_debug) {
            //     console.log("_inRangeYieldRates | - iteration: %s", i);
            // }

            if (uint256(rates[i].effectiveDay) * 1 days >= toTimestamp) {
                // if (_debug) {
                //     console.log(
                //         "-- _inRangeYieldRates | loop continue: effectiveDay >= toTimestamp: %s >= %s",
                //         rates[i].effectiveDay,
                //         toTimestamp
                //     );
                // }
                continue;
            }

            if (endIndex == 0) {
                endIndex = i;
            }

            // if (_debug) {
            //     console.log(
            //         "--  _inRangeYieldRates | loop include: effectiveDay=%s, value=%s",
            //         rates[i].effectiveDay,
            //         rates[i].value
            //     );
            // }

            if (uint256(rates[i].effectiveDay) * 1 days < fromTimestamp) {
                startIndex = i;
                // if (_debug) {
                //     console.log(
                //         "--  _inRangeYieldRates | loop break: effectiveDay < fromTimestamp: %s < %s",
                //         rates[i].effectiveDay,
                //         fromTimestamp
                //     );
                // }
                break;
            }
        } while (i > 0);

        // if (_debug) {
        //     console.log("");
        //     console.log("_inRangeYieldRates | Result yield rates:");
        //     for (uint256 k = startIndex; k <= endIndex; k++) {
        //         console.log("-- [%s] effectiveDay: %s, value: %s", k, rates[k].effectiveDay, rates[k].value);
        //     }

        //     console.log("");
        //     console.log("_inRangeYieldRates | END");
        // }

        return (startIndex, endIndex);
    }

    /**
     * @dev Aggregates the yield results.
     * @param yieldResults The yield results to aggregate.
     * @return The final accrued yield and stream yield.
     */
    function _aggregateYield(YieldResult[] memory yieldResults) private pure returns (uint256, uint256) {
        // bool _debug = false;

        // if (_debug) {
        //     console.log("");
        // }

        uint256 accruedYield = 0;
        uint256 streamYield = 0;

        if (yieldResults.length > 1) {
            // if (_debug) {
            //     console.log("_aggregateYield | accruedYield: %s += %s", accruedYield, yieldResults[0].lastDayPartialYield);
            // }
            accruedYield += yieldResults[0].lastDayPartialYield;
        }

        for (uint256 i = 0; i < yieldResults.length; i++) {
            // if (_debug) {
            //     console.log(
            //         "_aggregateYield | accruedYield: %s += %s + %s",
            //         accruedYield,
            //         yieldResults[i].firstDayPartialYield,
            //         yieldResults[i].fullDaysYield
            //     );
            // }
            accruedYield += yieldResults[i].firstDayPartialYield + yieldResults[i].fullDaysYield;
        }

        streamYield = yieldResults[yieldResults.length - 1].lastDayPartialYield;

        return (accruedYield, streamYield);
    }

    // ------------------ Timestamp ------------------------------- //

    /**
     * @dev Calculates a timestamp for the beginning of the next day.
     * @param timestamp The timestamp to calculate from.
     * @return The timestamp of the next day.
     */
    function _nextDay(uint256 timestamp) private pure returns (uint256) {
        return timestamp - (timestamp % 1 days) + 1 days;
    }

    /**
     * @dev Calculates the number of the effective day from a timestamp.
     * @param timestamp The timestamp to calculate from.
     * @return The number of the effective day.
     */
    function _effectiveDay(uint256 timestamp) private pure returns (uint256) {
        return timestamp / 1 days;
    }

    /**
     * @dev Calculates the remaining seconds before the next day.
     * @param timestamp The timestamp to calculate from.
     * @return The remaining seconds.
     */
    function _remainingSeconds(uint256 timestamp) private pure returns (uint256) {
        return timestamp % 1 days;
    }

    /**
     * @dev Calculates the timestamp of the beginning of the day.
     * @param timestamp The timestamp to calculate from.
     * @return The timestamp of the day.
     */
    function _effectiveTimestamp(uint256 timestamp) private pure returns (uint256) {
        return (timestamp / 1 days) * 1 days;
    }

    /**
     * @dev Calculates the block timestamp including the negative time shift.
     * @return The block timestamp.
     */
    function _blockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp - NEGATIVE_TIME_SHIFT;
    }

    // ------------------ Utility --------------------------------- //

    /**
     * @dev Truncates an array of yield rates.
     * @param startIndex The start index of the truncation.
     * @param endIndex The end index of the truncation.
     * @param rates The array to truncate.
     * @return The truncated array.
     */
    function _truncateArray(
        uint256 startIndex,
        uint256 endIndex,
        YieldRate[] storage rates
    ) private view returns (YieldRate[] memory) {
        YieldRate[] memory result = new YieldRate[](endIndex - startIndex + 1);
        for (uint256 i = startIndex; i <= endIndex; i++) {
            result[i - startIndex] = rates[i];
        }
        return result;
    }

    /**
     * @dev Calculates the fee for a given amount.
     * @param amount The amount to calculate the fee for.
     * @return The fee amount.
     */
    function _calculateFee(uint256 amount) private pure returns (uint256) {
        return (amount * FEE_RATE) / RATE_FACTOR;
    }

    /**
     * @dev Rounds down an amount.
     * @param amount The amount to round down.
     * @return The rounded down amount.
     */
    function _roundDown(uint256 amount) private pure returns (uint256) {
        return (amount / ROUND_FACTOR) * ROUND_FACTOR;
    }

    /**
     * @dev Rounds up an amount.
     * @param amount The amount to round up.
     * @return The rounded up amount.
     */
    function _roundUp(uint256 amount) private pure returns (uint256) {
        uint256 roundedAmount = _roundDown(amount);

        if (roundedAmount < amount) {
            roundedAmount += ROUND_FACTOR;
        }

        return roundedAmount;
    }

    /**
     * @dev Maps the accrue preview to a claim preview.
     * @param accrue The accrue preview.
     * @return The claim preview.
     */
    function _map(AccruePreview memory accrue) private pure returns (ClaimPreview memory) {
        ClaimPreview memory claim;
        uint256 totalYield = accrue.accruedYieldAfter + accrue.streamYieldAfter;
        claim.yield = _roundDown(totalYield);
        claim.fee = 0;
        claim.balance = accrue.balance;
        claim.rate = accrue.rates[accrue.rates.length - 1].value;
        return claim;
    }

    // ------------------ Overrides ------------------------------- //

    /**
     * @dev Initializes a single account.
     * @param account The account to initialize.
     */
    function _initializeSingleAccount(address account) internal virtual;
}
