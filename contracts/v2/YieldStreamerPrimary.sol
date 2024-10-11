// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "hardhat/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { YieldStreamerStorage } from "./YieldStreamerStorage.sol";
import { IYieldStreamerPrimary_Errors } from "./interfaces/IYieldStreamerPrimary.sol";
import { IYieldStreamerPrimary_Events } from "./interfaces/IYieldStreamerPrimary.sol";
import { IERC20Hook } from "../interfaces/IERC20Hook.sol";

/**
 * @title YieldStreamerPrimary contract
 * @author CloudWalk Inc. (See https://www.cloudwalk.io)
 * @dev The contract that responsible for calculating and distributing the yield.
 */
abstract contract YieldStreamerPrimary is
    YieldStreamerStorage,
    IYieldStreamerPrimary_Errors,
    IYieldStreamerPrimary_Events,
    IERC20Hook
{
    // -------------------- Libs ---------------------------------- //

    using SafeCast for uint256;

    // -------------------- Structs ------------------------------- //

    /**
     * @dev Structure that represents a range of values.
     *
     * Fields:
     *  - startIndex: -- The value the range starts at.
     *  - endIndex: ---- The value the range ends at.
     */
    struct Range {
        uint256 startIndex;
        uint256 endIndex;
    }

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
     *  - initialBalance: ------- The initial balance at the period start.
     *  - initialAccruedYield: -- The initial accrued yield at the period start.
     *  - initialStreamYield: --- The initial stream yield at the period start.
     *  - yieldRateRange: ------- The range of yield rates that are applicable for the period.
     */
    struct CalculateYieldParams {
        uint256 fromTimestamp;
        uint256 toTimestamp;
        uint256 initialBalance;
        uint256 initialAccruedYield;
        uint256 initialStreamYield;
        Range yieldRateRange;
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
        if (from != address(0) && from.code.length == 0) {
            _initializeYieldState(from);
            _decreaseTokenBalance(from, amount);
        }

        if (to != address(0) && to.code.length == 0) {
            _initializeYieldState(to);
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
        YieldRate[] storage rates = $.yieldRates[$.groups[account].id];

        _accrueYield_NEW(account, state, rates);
        _transferYield(account, amount, state, $.feeReceiver, $.underlyingToken);
    }

    /**
     * @dev Increases the token balance for a given account.
     * @param account The account to increase the token balance for.
     * @param amount The amount of token to increase.
     */
    function _increaseTokenBalance(address account, uint256 amount) internal {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldState storage state = $.yieldStates[account];
        YieldRate[] storage rates = $.yieldRates[$.groups[account].id];
        _accrueYield_NEW(account, state, rates);
        state.balanceAtLastUpdate += amount.toUint64();
    }

    /**
     * @dev Decreases the token balance for a given account.
     * @param account The account to decrease the token balance for.
     * @param amount The amount of token to decrease.
     */
    function _decreaseTokenBalance(address account, uint256 amount) internal {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldState storage state = $.yieldStates[account];
        YieldRate[] storage rates = $.yieldRates[$.groups[account].id];
        _accrueYield_NEW(account, state, rates);
        state.balanceAtLastUpdate -= amount.toUint64();
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
        address account, // Format: prevent collapse
        uint256 amount,
        YieldState storage state,
        address feeReceiver,
        address token
    ) internal {
        uint256 totalYield = state.accruedYield + state.streamYield;

        if (amount > totalYield) {
            revert YieldStreamer_YieldBalanceInsufficient();
        }

        if (amount > state.accruedYield) {
            emit YieldStreamer_YieldTransferred(account, state.accruedYield, amount - state.accruedYield);
            state.streamYield -= (amount - state.accruedYield).toUint64();
            state.accruedYield = 0;
        } else {
            emit YieldStreamer_YieldTransferred(account, amount, 0);
            state.accruedYield -= amount.toUint64();
        }

        if (FEE_RATE != 0 && feeReceiver != address(0)) {
            uint256 fee = _roundUp(_calculateFee(amount));
            amount -= fee;
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
        return _map(_getAccruePreview(state, rates));
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
    ) internal view returns (AccruePreview memory) {
        AccruePreview memory preview;

        preview.accruedYieldBefore = state.accruedYield;
        preview.streamYieldBefore = state.streamYield;
        preview.fromTimestamp = state.timestampAtLastUpdate;
        preview.toTimestamp = _blockTimestamp();

        Range memory yieldRateRange = _inRangeYieldRates(rates, preview.fromTimestamp, preview.toTimestamp);

        CalculateYieldParams memory calculateParams = CalculateYieldParams(
            preview.fromTimestamp,
            preview.toTimestamp,
            state.balanceAtLastUpdate,
            preview.accruedYieldBefore,
            preview.streamYieldBefore,
            yieldRateRange
        );

        YieldResult[] memory calculateResults = _calculateYield(calculateParams, rates);
        (preview.accruedYieldAfter, preview.streamYieldAfter) = _aggregateYield(calculateResults);
        preview.accruedYieldAfter += preview.accruedYieldBefore;

        preview.rates = _truncateArray(yieldRateRange, rates);
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
    function _accrueYield_NEW(
        address account, // Tools: this comment prevents Prettier from formatting into a single line.
        YieldState storage state,
        YieldRate[] storage rates
    ) internal {
        AccruePreview memory preview = _getAccruePreview(state, rates);

        emit YieldStreamer_YieldAccrued(
            account,
            preview.accruedYieldAfter,
            preview.streamYieldAfter,
            preview.accruedYieldBefore,
            preview.streamYieldBefore
        );

        state.timestampAtLastUpdate = preview.toTimestamp.toUint64();
        state.accruedYield = preview.accruedYieldAfter.toUint64();
        state.streamYield = preview.streamYieldAfter.toUint64();
    }

    /**
     * @dev Accrues the yield for a given account and period.
     * @param account The account to accrue the yield for.
     * @param state The current state of the yield.
     * @param fromTimestamp The timestamp of the period start.
     * @param toTimestamp The timestamp of the period end.
     */
    function _accrueYield(
        address account,
        YieldState storage state,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) internal virtual {
        YieldStreamerStorageLayout storage $ = _yieldStreamerStorage();
        YieldRate[] storage yieldRates = $.yieldRates[$.groups[account].id];

        // bool _debug = false;

        // if (_debug) {
        //     console.log("");
        //     console.log("_accrueYield | START");
        //     console.log("_accrueYield | - account: %s", account);
        //     console.log("_accrueYield | - fromTime: %s, toTime: %s", fromTimestamp, toTimestamp);
        //     console.log(
        //         "_accrueYield | - fromDay: %s, toDay: %s",
        //         _effectiveDay(fromTimestamp),
        //         _effectiveDay(toTimestamp)
        //     );

        //     console.log("");
        //     console.log("_accrueYield | State before accrual: %s", account);
        //     console.log("_accrueYield | - timestampAtLastUpdate: %s", state.timestampAtLastUpdate);
        //     console.log("_accrueYield | - balanceAtLastUpdate: %s", state.balanceAtLastUpdate);
        //     console.log("_accrueYield | - accruedYield: %s", state.accruedYield);
        //     console.log("_accrueYield | - streamYield: %s", state.streamYield);
        // }

        Range memory yieldRateRange = _inRangeYieldRates(yieldRates, fromTimestamp, toTimestamp);

        CalculateYieldParams memory calculateParams = CalculateYieldParams(
            fromTimestamp,
            toTimestamp,
            state.balanceAtLastUpdate,
            state.accruedYield,
            state.streamYield,
            yieldRateRange
        );

        YieldResult[] memory calculateResults = _calculateYield(calculateParams, yieldRates);
        (uint256 accruedYield, uint256 streamYield) = _aggregateYield(calculateResults);
        accruedYield += state.accruedYield;

        emit YieldStreamer_YieldAccrued(account, accruedYield, streamYield, state.accruedYield, state.streamYield);

        state.timestampAtLastUpdate = _blockTimestamp().toUint64();
        state.accruedYield = accruedYield.toUint64();
        state.streamYield = streamYield.toUint64();

        // if (_debug) {
        //     console.log("");
        //     console.log("_accrueYield | State after accrual: %s", account);
        //     console.log("_accrueYield | - timestampAtLastUpdate: %s", state.timestampAtLastUpdate);
        //     console.log("_accrueYield | - balanceAtLastUpdate: %s", state.balanceAtLastUpdate);
        //     console.log("_accrueYield | - accruedYield: %s", state.accruedYield);
        //     console.log("_accrueYield | - streamYield: %s", state.streamYield);

        //     console.log("");
        //     console.log("_accrueYield | END");
        // }
    }

    /**
     * @dev Calculates the yield for a given period.
     * @param params The parameters for the yield calculation.
     * @param yieldRates The array of yield rates to use for the calculation.
     * @return The yield results for the given period.
     */
    function _calculateYield(
        CalculateYieldParams memory params,
        YieldRate[] storage yieldRates // Format: prevent collapse
    ) internal view returns (YieldResult[] memory) {
        YieldResult[] memory results;
        uint256 ratePeriods = params.yieldRateRange.endIndex - params.yieldRateRange.startIndex + 1;
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
        //     console.log("_calculateYield | - yieldRates:");
        //     for (uint256 i = params.yieldRateRange.startIndex; i <= params.yieldRateRange.endIndex; i++) {
        //         console.log(
        //             "_calculateYield | -- [%s] day: %s, value: %s",
        //             i,
        //             yieldRates[i].effectiveDay,
        //             yieldRates[i].value
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
            //     console.log("_calculateYield | - yieldRate: %s", yieldRates[params.yieldRateRange.startIndex].value);
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
                    yieldRates[params.yieldRateRange.startIndex].value,
                    params.initialBalance + params.initialAccruedYield,
                    params.initialStreamYield
                )
            );

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Result:");
            //     console.log("_calculateYield | - firstDayYield: %s", result[0].firstDayYield);
            //     console.log("_calculateYield | - fullDaysYield: %s", result[0].fullDaysYield);
            //     console.log("_calculateYield | - lastDayYield: %s", result[0].lastDayYield);
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
            localToTimestamp = yieldRates[params.yieldRateRange.startIndex + 1].effectiveDay * 1 days;

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Calculating yield for first period:");
            //     console.log("_calculateYield | - yieldRate: %s", yieldRates[params.yieldRateRange.startIndex].value);
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
                    yieldRates[params.yieldRateRange.startIndex].value,
                    params.initialBalance + params.initialAccruedYield,
                    params.initialStreamYield
                )
            );

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Result:");
            //     console.log("_calculateYield | - firstDayYield: %s", result[0].firstDayYield);
            //     console.log("_calculateYield | - fullDaysYield: %s", result[0].fullDaysYield);
            //     console.log("_calculateYield | - lastDayYield: %s", result[0].lastDayYield);
            // }

            localFromTimestamp = localToTimestamp;
            localToTimestamp = params.toTimestamp;

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Calculating yield for second period:");
            //     console.log(
            //         " _calculateYield | - yieldRate: %s",
            //         yieldRates[params.yieldRateRange.startIndex + 1].value
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
                    yieldRates[params.yieldRateRange.startIndex + 1].value,
                    params.initialBalance +
                        params.initialAccruedYield +
                        results[0].firstDayYield +
                        results[0].fullDaysYield +
                        results[0].lastDayYield,
                    params.initialStreamYield
                )
            );

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Result:");
            //     console.log("_calculateYield | - firstDayYield: %s", result[1].firstDayYield);
            //     console.log("_calculateYield | - fullDaysYield: %s", result[1].fullDaysYield);
            //     console.log("_calculateYield | - lastDayYield: %s", result[1].lastDayYield);
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
            localToTimestamp = yieldRates[params.yieldRateRange.startIndex + 1].effectiveDay * 1 days;

            // Calculate yield for the first period

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Calculating yield for first period:");
            //     console.log("_calculateYield | - yieldRate: %s", yieldRates[params.yieldRateRange.startIndex].value);
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
                    yieldRates[params.yieldRateRange.startIndex].value,
                    currentBalance,
                    params.initialStreamYield
                )
            );

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | First period result:");
            //     console.log("_calculateYield | - firstDayYield: %s", result[0].firstDayYield);
            //     console.log("_calculateYield | - fullDaysYield: %s", result[0].fullDaysYield);
            //     console.log("_calculateYield | - lastDayYield: %s", result[0].lastDayYield);
            // }

            currentBalance += results[0].firstDayYield + results[0].fullDaysYield + results[0].lastDayYield;

            // Calculate yield for the intermediate periods

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Calculating yield for full %s periods:", ratePeriods - 2);
            // }

            for (uint256 i = params.yieldRateRange.startIndex + 1; i < params.yieldRateRange.endIndex; i++) {
                localFromTimestamp = yieldRates[i].effectiveDay * 1 days;
                localToTimestamp = yieldRates[i + 1].effectiveDay * 1 days;

                // if (_debug) {
                //     console.log("");
                //     console.log("_calculateYield | Period #%s:", i);
                //     console.log("_calculateYield | - yieldRate: %s", yieldRates[i].value);
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

                results[i - params.yieldRateRange.startIndex] = _compoundYield(
                    CompoundYieldParams(localFromTimestamp, localToTimestamp, yieldRates[i].value, currentBalance, 0)
                );

                // if (_debug) {
                //     console.log("");
                //     console.log("_calculateYield | Full period result: %s", i);
                //     console.log(
                //         "_calculateYield | - firstDayYield: %s",
                //         result[i - params.yieldRateRange.startIndex].firstDayYield
                //     );
                //     console.log(
                //         "_calculateYield | - fullDaysYield: %s",
                //         result[i - params.yieldRateRange.startIndex].fullDaysYield
                //     );
                //     console.log(
                //         "_calculateYield | - lastDayYield: %s",
                //         result[i - params.yieldRateRange.startIndex].lastDayYield
                //     );
                // }

                currentBalance +=
                    results[i - params.yieldRateRange.startIndex].firstDayYield +
                    results[i - params.yieldRateRange.startIndex].fullDaysYield +
                    results[i - params.yieldRateRange.startIndex].lastDayYield;
            }

            // Calculate yield for the last period

            localFromTimestamp = yieldRates[params.yieldRateRange.startIndex + ratePeriods - 1].effectiveDay * 1 days;
            localToTimestamp = params.toTimestamp;

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | - Calculating yield for last period:");
            //     console.log(
            //         " _calculateYield | -- yieldRate: %s",
            //         yieldRates[params.yieldRateRange.startIndex + ratePeriods - 1].value
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
                    yieldRates[params.yieldRateRange.startIndex + ratePeriods - 1].value,
                    currentBalance,
                    0
                )
            );

            // if (_debug) {
            //     console.log("");
            //     console.log("_calculateYield | Last period result:");
            //     console.log("_calculateYield | - firstDayYield: %s", result[ratePeriods - 1].firstDayYield);
            //     console.log("_calculateYield | - fullDaysYield: %s", result[ratePeriods - 1].fullDaysYield);
            //     console.log("_calculateYield | - lastDayYield: %s", result[ratePeriods - 1].lastDayYield);
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
    function _compoundYield(CompoundYieldParams memory params) internal pure returns (YieldResult memory) {
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
            result.lastDayYield = params.streamYield + partDayYield;

            // if (_debug) {
            //     console.log("");
            //     console.log("_compoundYield | Case 1: Within the same day");

            //     console.log("");
            //     console.log("_compoundYield | Calculating yield for elapsed time: %s", toTimestamp - fromTimestamp);
            //     console.log(
            //         "_compoundYield | - lastDayYield = streamYield + partDayYield: %s + %s = %s",
            //         streamYield,
            //         partDayYield,
            //         result.lastDayYield
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
                result.firstDayYield = params.streamYield + partDayYield;

                // if (_debug) {
                //     console.log("");
                //     console.log(
                //         "_compoundYield | Calculating yield for the first partial day remaining seconds %s",
                //         firstDaySeconds
                //     );
                //     console.log(
                //         "_compoundYield | - firstDayYield = streamYield + partDayYield: %s + %s = %s",
                //         streamYield,
                //         partDayYield,
                //         result.firstDayYield
                //     );
                // }

                totalBalance += result.firstDayYield;
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
                result.lastDayYield = _calculatePartDayYield(totalBalance, params.yieldRate, lastDaySeconds);

                // if (_debug) {
                //     console.log("_compoundYield | - last day remaining seconds: %s", lastDaySeconds);
                //     console.log("_compoundYield | - last day partial yield: %s", result.lastDayYield);
                // }
            }
        }

        // if (_debug) {
        //     console.log("");
        //     console.log("_compoundYield | Final result:");
        //     console.log("_compoundYield | - firstDayYield: %s", result.firstDayYield);
        //     console.log("_compoundYield | - fullDaysYield: %s", result.fullDaysYield);
        //     console.log("_compoundYield | - lastDayYield: %s", result.lastDayYield);

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
    ) internal pure returns (uint256) {
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
    ) internal pure returns (uint256) {
        return (amount * yieldRate) / RATE_FACTOR;
    }

    /**
     * @dev Finds the yield rates within a given timestamp range.
     * @param yieldRates The array of yield rates to search.
     * @param fromTimestamp The start timestamp.
     * @param toTimestamp The end timestamp.
     * @return The yield rate range.
     */
    function _inRangeYieldRates(
        YieldRate[] storage yieldRates,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) internal view returns (Range memory) {
        // bool _debug = false;

        // if (_debug) {
        //     console.log("");
        //     console.log("_inRangeYieldRates | START");
        //     console.log("_inRangeYieldRates | Getting yield rates from %s to %s", fromTimestamp, toTimestamp);

        //     console.log("");
        //     console.log("_inRangeYieldRates | Input yield rates:");
        //     for (uint256 k = 0; k < yieldRates.length; k++) {
        //         console.log(
        //             "_inRangeYieldRates | - [%s] effectiveDay: %s, value: %s",
        //             k,
        //             yieldRates[k].effectiveDay,
        //             yieldRates[k].value
        //         );
        //     }

        //     console.log("");
        //     console.log("_inRangeYieldRates | Starting loop:");
        // }

        Range memory range;

        uint256 i = yieldRates.length;

        do {
            i--;

            // if (_debug) {
            //     console.log("_inRangeYieldRates | - iteration: %s", i);
            // }

            if (yieldRates[i].effectiveDay * 1 days >= toTimestamp) {
                // if (_debug) {
                //     console.log(
                //         "-- _inRangeYieldRates | loop continue: effectiveDay >= toTimestamp: %s >= %s",
                //         yieldRates[i].effectiveDay,
                //         toTimestamp
                //     );
                // }
                continue;
            }

            if (range.endIndex == 0) {
                range.endIndex = i;
            }

            // if (_debug) {
            //     console.log(
            //         "--  _inRangeYieldRates | loop include: effectiveDay=%s, value=%s",
            //         yieldRates[i].effectiveDay,
            //         yieldRates[i].value
            //     );
            // }

            if (yieldRates[i].effectiveDay * 1 days < fromTimestamp) {
                range.startIndex = i;
                // if (_debug) {
                //     console.log(
                //         "--  _inRangeYieldRates | loop break: effectiveDay < fromTimestamp: %s < %s",
                //         yieldRates[i].effectiveDay,
                //         fromTimestamp
                //     );
                // }
                break;
            }
        } while (i > 0);

        // if (_debug) {
        //     console.log("");
        //     console.log("_inRangeYieldRates | Result yield rates:");
        //     for (uint256 k = range.startIndex; k <= range.endIndex; k++) {
        //         console.log("-- [%s] effectiveDay: %s, value: %s", k, yieldRates[k].effectiveDay, yieldRates[k].value);
        //     }

        //     console.log("");
        //     console.log("_inRangeYieldRates | END");
        // }

        return range;
    }

    /**
     * @dev Aggregates the yield results.
     * @param yieldResults The yield results to aggregate.
     * @return The final accrued yield and stream yield.
     */
    function _aggregateYield(YieldResult[] memory yieldResults) internal pure returns (uint256, uint256) {
        // bool _debug = false;

        // if (_debug) {
        //     console.log("");
        // }

        uint256 accruedYield = 0;
        uint256 streamYield = 0;

        if (yieldResults.length > 1) {
            // if (_debug) {
            //     console.log("_aggregateYield | accruedYield: %s += %s", accruedYield, yieldResults[0].lastDayYield);
            // }
            accruedYield += yieldResults[0].lastDayYield;
        }

        for (uint256 i = 0; i < yieldResults.length; i++) {
            // if (_debug) {
            //     console.log(
            //         "_aggregateYield | accruedYield: %s += %s + %s",
            //         accruedYield,
            //         yieldResults[i].firstDayYield,
            //         yieldResults[i].fullDaysYield
            //     );
            // }
            accruedYield += yieldResults[i].firstDayYield + yieldResults[i].fullDaysYield;
        }

        streamYield = yieldResults[yieldResults.length - 1].lastDayYield;

        return (accruedYield, streamYield);
    }

    // ------------------ Timestamp ------------------------------- //

    /**
     * @dev Calculates a timestamp for the beginning of the next day.
     * @param timestamp The timestamp to calculate from.
     * @return The timestamp of the next day.
     */
    function _nextDay(uint256 timestamp) internal pure returns (uint256) {
        return timestamp - (timestamp % 1 days) + 1 days;
    }

    /**
     * @dev Calculates the number of the effective day from a timestamp.
     * @param timestamp The timestamp to calculate from.
     * @return The number of the effective day.
     */
    function _effectiveDay(uint256 timestamp) internal pure returns (uint256) {
        return timestamp / 1 days;
    }

    /**
     * @dev Calculates the remaining seconds before the next day.
     * @param timestamp The timestamp to calculate from.
     * @return The remaining seconds.
     */
    function _remainingSeconds(uint256 timestamp) internal pure returns (uint256) {
        return timestamp % 1 days;
    }

    /**
     * @dev Calculates the timestamp of the beginning of the day.
     * @param timestamp The timestamp to calculate from.
     * @return The timestamp of the day.
     */
    function _effectiveTimestamp(uint256 timestamp) internal pure returns (uint256) {
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
     * @param range The range describing the truncation.
     * @param yieldRates The array to truncate.
     * @return The truncated array.
     */
    function _truncateArray(
        Range memory range,
        YieldRate[] storage yieldRates
    ) internal view returns (YieldRate[] memory) {
        YieldRate[] memory result = new YieldRate[](range.endIndex - range.startIndex + 1);
        for (uint256 i = range.startIndex; i <= range.endIndex; i++) {
            result[i - range.startIndex] = yieldRates[i];
        }
        return result;
    }

    /**
     * @dev Calculates the fee for a given amount.
     * @param amount The amount to calculate the fee for.
     * @return The fee amount.
     */
    function _calculateFee(uint256 amount) internal pure returns (uint256) {
        return (amount * FEE_RATE) / RATE_FACTOR;
    }

    /**
     * @dev Rounds down an amount.
     * @param amount The amount to round down.
     * @return The rounded down amount.
     */
    function _roundDown(uint256 amount) internal pure returns (uint256) {
        return (amount / ROUND_FACTOR) * ROUND_FACTOR;
    }

    /**
     * @dev Rounds up an amount.
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

    /**
     * @dev Maps the accrue preview to a claim preview.
     * @param accrue The accrue preview.
     * @return The claim preview.
     */
    function _map(AccruePreview memory accrue) internal pure returns (ClaimPreview memory) {
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
     * @dev Initializes the yield state for the given account.
     * @param account The account to initialize.
     */
    function _initializeYieldState(address account) internal virtual;
}
