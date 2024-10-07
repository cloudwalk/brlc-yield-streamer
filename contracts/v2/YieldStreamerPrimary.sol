// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "hardhat/console.sol";

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import { IYieldStreamerPrimary } from "./interfaces/IYieldStreamerPrimary.sol";
import { YieldStreamerStorage } from "./YieldStreamerStorage.sol";
import { IERC20Hook } from "../interfaces/IERC20Hook.sol";

contract YieldStreamerPrimary is YieldStreamerStorage, IYieldStreamerPrimary, IERC20Hook {
    // -------------------- Structs -------------------- //

    struct CalculateYieldParams {
        uint256 fromTimestamp;
        uint256 toTimestamp;
        uint256 initialBalance;
        uint256 initialAccruedYield;
        uint256 initialStreamYield;
        uint256 startIndex;
        YieldRate[] yieldRates;
    }

    // -------------------- IERC20Hook -------------------- //

    /// @inheritdoc IERC20Hook
    function beforeTokenTransfer(address from, address to, uint256 amount) external {
        // Do nothing
    }

    /// @inheritdoc IERC20Hook
    function afterTokenTransfer(address from, address to, uint256 amount) external {
        if (_validateAccount(from)) {
            _initializeYieldState(from);
            _decreaseTokenBalance(from, amount);
        }

        if (_validateAccount(to)) {
            _initializeYieldState(to);
            _increaseTokenBalance(to, amount);
        }
    }

    function _validateAccount(address account) internal pure returns (bool) {
        // TODO: add other validations:
        // - account is not a contract
        // - etc.
        return account != address(0);
    }

    function _initializeYieldState(address account) internal pure {
        // TODO: intialize yield state from the old yield streamer contract
    }

    // -------------------- Functions -------------------- //

    function claimAllFor(address account) external {
        YieldState storage state = _yieldStates[account];
        _accrueYield(account, state, state.timestampAtLastUpdate, _blockTimestamp());
        _transferYield(account, state.accruedYield, state);
    }

    function claimAmountFor(address account, uint256 amount) external {
        YieldState storage state = _yieldStates[account];
        _accrueYield(account, state, state.timestampAtLastUpdate, _blockTimestamp());
        _transferYield(account, amount, state);
    }

    function getYieldState(address account) external view returns (YieldState memory state) {
        state = _yieldStates[account];
    }

    function getYieldBalance(address account) external view returns (YieldBalance memory balance) {
        balance = getClaimPreview(account).balance;
    }

    function getClaimPreview(address account) public view returns (ClaimPreview memory preview) {
        YieldState memory state = _yieldStates[account];
        uint256 fromTimestamp = state.timestampAtLastUpdate;
        uint256 toTimestamp = _blockTimestamp();

        (YieldRate[] memory inRangeYieldRates, uint256 inRangeStartIndex) = _inRangeYieldRates(
            _yieldRates[_groups[account]],
            fromTimestamp,
            toTimestamp
        );

        CalculateYieldParams memory calculateParams = CalculateYieldParams(
            fromTimestamp,
            toTimestamp,
            state.balanceAtLastUpdate,
            state.accruedYield,
            state.streamYield,
            inRangeStartIndex,
            inRangeYieldRates
        );

        YieldResult[] memory calculateResults = _calculateYield(calculateParams);
        (uint256 accruedYield, uint256 streamYield) = _aggregateYield(calculateResults);
        accruedYield += state.accruedYield;

        preview.balance = YieldBalance(accruedYield, streamYield);
        preview.yieldRates = _truncateArray(inRangeYieldRates, inRangeStartIndex);
        preview.yieldResults = calculateResults;
    }

    // -------------------- Internal -------------------- //

    function _increaseTokenBalance(address account, uint256 amount) internal {
        YieldState storage state = _yieldStates[account];
        _accrueYield(account, state, state.timestampAtLastUpdate, _blockTimestamp());
        state.balanceAtLastUpdate += amount;
    }

    function _decreaseTokenBalance(address account, uint256 amount) internal {
        YieldState storage state = _yieldStates[account];
        _accrueYield(account, state, state.timestampAtLastUpdate, _blockTimestamp());
        state.balanceAtLastUpdate -= amount;
    }

    function _accrueYield(
        address account,
        YieldState storage state,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) internal {
        bool _debug = true;

        if (_debug) {
            console.log("");
            console.log("_accrueYield | START");
            console.log("_accrueYield | - account: %s", account);
            console.log("_accrueYield | - fromTime: %s, toTime: %s", fromTimestamp, toTimestamp);
            console.log(
                "_accrueYield | - fromDay: %s, toDay: %s",
                _effectiveDay(fromTimestamp),
                _effectiveDay(toTimestamp)
            );

            console.log("");
            console.log("_accrueYield | State before accrual: %s", account);
            console.log("_accrueYield | - timestampAtLastUpdate: %s", state.timestampAtLastUpdate);
            console.log("_accrueYield | - balanceAtLastUpdate: %s", state.balanceAtLastUpdate);
            console.log("_accrueYield | - accruedYield: %s", state.accruedYield);
            console.log("_accrueYield | - streamYield: %s", state.streamYield);
        }

        (YieldRate[] memory inRangeYieldRates, uint256 inRangeStartIndex) = _inRangeYieldRates(
            _yieldRates[_groups[account]],
            fromTimestamp,
            toTimestamp
        );

        CalculateYieldParams memory calculateParams = CalculateYieldParams(
            fromTimestamp,
            toTimestamp,
            state.balanceAtLastUpdate,
            state.accruedYield,
            state.streamYield,
            inRangeStartIndex,
            inRangeYieldRates
        );

        YieldResult[] memory calculateResults = _calculateYield(calculateParams);
        (uint256 accruedYield, uint256 streamYield) = _aggregateYield(calculateResults);
        accruedYield += state.accruedYield;

        emit YieldStreamer_YieldAccrued(account, accruedYield, streamYield, state.accruedYield, state.streamYield);

        state.timestampAtLastUpdate = _blockTimestamp();
        state.accruedYield = accruedYield;
        state.streamYield = streamYield;

        if (_debug) {
            console.log("");
            console.log("_accrueYield | State after accrual: %s", account);
            console.log("_accrueYield | - timestampAtLastUpdate: %s", state.timestampAtLastUpdate);
            console.log("_accrueYield | - balanceAtLastUpdate: %s", state.balanceAtLastUpdate);
            console.log("_accrueYield | - accruedYield: %s", state.accruedYield);
            console.log("_accrueYield | - streamYield: %s", state.streamYield);

            console.log("");
            console.log("_accrueYield | END");
        }
    }

    function _transferYield(
        address account, // Format: prevent collapse
        uint256 amount,
        YieldState storage state
    ) internal {
        uint256 totalYield = state.accruedYield + state.streamYield;

        if (amount > totalYield) {
            revert YieldStreamer_InsufficientYieldBalance();
        }

        if (amount > state.accruedYield) {
            emit YieldStreamer_YieldTransferred(account, state.accruedYield, amount - state.accruedYield);
            state.streamYield -= (amount - state.accruedYield);
            state.accruedYield = 0;
        } else {
            emit YieldStreamer_YieldTransferred(account, amount, 0);
            state.accruedYield -= amount;
        }

        IERC20Upgradeable(underlyingToken).transfer(account, amount);
    }

    function _compoundYield(
        uint256 fromTimestamp,
        uint256 toTimestamp,
        uint256 yieldRate,
        uint256 balance,
        uint256 streamYield
    ) internal pure returns (YieldResult memory result) {
        bool _debug = true;

        if (_debug) {
            console.log("");
            console.log("_compoundYield | START");
        }

        if (_debug) {
            console.log("");
            console.log("_compoundYield | Input params:");
            console.log("_compoundYield | - fromTimestamp: %s", fromTimestamp);
            console.log("_compoundYield | - toTimestamp: %s", toTimestamp);
            console.log("_compoundYield | - yieldRate: %s", yieldRate);
            console.log("_compoundYield | - balance: %s", balance);
            console.log("_compoundYield | - streamYield: %s", streamYield);
        }

        if (fromTimestamp > toTimestamp) {
            revert YieldStreamer_InvalidTimeRange();
        }
        if (fromTimestamp == toTimestamp || balance == 0) {
            if (_debug) {
                console.log("");
                console.log("_compoundYield | Case 0: Early exit");
                console.log("");
                console.log("_compoundYield | END");
            }
            return YieldResult(0, 0, 0);
        }

        uint256 totalBalance = balance;
        uint256 nextDayStart = _nextDay(fromTimestamp);
        uint256 partDayYield = 0;

        if (nextDayStart >= toTimestamp) {
            /**
             * We are within the same day as the `fromTimestamp`.
             */

            partDayYield = _calculatePartDayYield(totalBalance, yieldRate, toTimestamp - fromTimestamp);
            result.lastDayYield = streamYield + partDayYield;

            if (_debug) {
                console.log("");
                console.log("_compoundYield | Case 1: Within the same day");
                console.log("");
                console.log("_compoundYield | Calculating yield for elapsed time: %s", toTimestamp - fromTimestamp);
                console.log(
                    "_compoundYield | - lastDayYield = streamYield + partDayYield: %s + %s = %s",
                    streamYield,
                    partDayYield,
                    result.lastDayYield
                );
            }
        } else {
            /**
             * We are spanning multiple days.
             */

            if (_debug) {
                console.log("");
                console.log("_compoundYield | Case 2: Spanning multiple days");
            }

            /**
             * 1. Calculate yield for the first partial day.
             */

            uint256 firstDaySeconds = nextDayStart - fromTimestamp;

            if (firstDaySeconds != 1 days) {
                partDayYield = _calculatePartDayYield(totalBalance, yieldRate, firstDaySeconds);
                result.firstDayYield = streamYield + partDayYield;

                if (_debug) {
                    console.log("");
                    console.log(
                        "_compoundYield | Calculating yield for the first partial day remaining seconds %s",
                        firstDaySeconds
                    );
                    console.log(
                        "_compoundYield | - firstDayYield = streamYield + partDayYield: %s + %s = %s",
                        streamYield,
                        partDayYield,
                        result.firstDayYield
                    );
                }

                totalBalance += result.firstDayYield;
                fromTimestamp = nextDayStart;
            }

            /**
             * 2. Calculate yield for each full day.
             */

            uint256 fullDaysCount = (toTimestamp - fromTimestamp) / 1 days;

            if (fullDaysCount > 0) {
                if (_debug) {
                    console.log("");
                    console.log("_compoundYield | Calculating yield for full days count: %s", fullDaysCount);
                }

                for (uint256 i = 0; i < fullDaysCount; i++) {
                    uint256 dailyYield = _calculateFullDayYield(totalBalance + result.fullDaysYield, yieldRate);
                    result.fullDaysYield += dailyYield;

                    if (_debug) {
                        console.log("_compoundYield | - [%s] full day yield: %s", i, dailyYield);
                    }
                }

                totalBalance += result.fullDaysYield;
                fromTimestamp += fullDaysCount * 1 days;
            }

            /**
             * 3. Calculate yield for the last partial day.
             */

            if (fromTimestamp < toTimestamp) {
                if (_debug) {
                    console.log("");
                    console.log("_compoundYield | Calculating yield for the last partial day");
                }

                uint256 lastDaySeconds = toTimestamp - fromTimestamp;
                result.lastDayYield = _calculatePartDayYield(totalBalance, yieldRate, lastDaySeconds);

                if (_debug) {
                    console.log("_compoundYield | - last day remaining seconds: %s", lastDaySeconds);
                    console.log("_compoundYield | - last day partial yield: %s", result.lastDayYield);
                }
            }
        }

        if (_debug) {
            console.log("");
            console.log("_compoundYield | Final result:");
            console.log("_compoundYield | - firstDayYield: %s", result.firstDayYield);
            console.log("_compoundYield | - fullDaysYield: %s", result.fullDaysYield);
            console.log("_compoundYield | - lastDayYield: %s", result.lastDayYield);
            console.log("");
            console.log("_compoundYield | END");
        }
    }

    function _calculateYield(
        CalculateYieldParams memory params // Format: prevent collapse
    ) internal pure returns (YieldResult[] memory result) {
        uint256 ratePeriods = params.yieldRates.length - params.startIndex;
        uint256 localFromTimestamp = params.fromTimestamp;
        uint256 localToTimestamp = params.toTimestamp;

        // TODO: Double-check inclusion of the last second!!

        bool _debug = true;

        if (_debug) {
            console.log("");
            console.log("_calculateYield | START");
        }

        if (_debug) {
            console.log("");
            console.log("_calculateYield | Input params:");
            console.log("_calculateYield | - initialBalance: %s", params.initialBalance);
            console.log("_calculateYield | - initialAccruedYield: %s", params.initialAccruedYield);
            console.log("_calculateYield | - initialStreamYield: %s", params.initialStreamYield);
            console.log(
                "_calculateYield | - fromTimestamp: %s (day: %s + seconds: %s)",
                localFromTimestamp,
                _effectiveDay(localFromTimestamp),
                _remainingSeconds(localFromTimestamp)
            );
            console.log(
                "_calculateYield | - toTimestamp: %s (day: %s + seconds: %s)",
                localToTimestamp,
                _effectiveDay(localToTimestamp),
                _remainingSeconds(localToTimestamp)
            );
            console.log("_calculateYield | - yieldRates:");
            for (uint256 i = params.startIndex; i < params.yieldRates.length; i++) {
                console.log(
                    "_calculateYield | -- [%s] day: %s, value: %s",
                    i,
                    params.yieldRates[i].effectiveDay,
                    params.yieldRates[i].value
                );
            }
        }

        if (ratePeriods == 0) {
            /**
             * Scenario 0
             * If there are no yield rate periods in the range, we return an empty array.
             */

            if (_debug) {
                console.log("");
                console.log("_calculateYield | Scenario 0: No yield rates in range");
            }

            result = new YieldResult[](0);
        } else if (ratePeriods == 1) {
            /**
             * Scenario 1
             * If there is only one yield rate period in the range, we calculate the yield for the entire range
             * using this yield rate.
             */

            if (_debug) {
                console.log("");
                console.log("_calculateYield | Scenario 1: One yield rate in range");
                console.log("");
                console.log("_calculateYield | Calculating yield:");
                console.log("_calculateYield | - yieldRate: %s", params.yieldRates[params.startIndex].value);
                console.log(
                    "_calculateYield | - fromTimestamp: %s (day: %s + seconds: %s)",
                    localFromTimestamp,
                    _effectiveDay(localFromTimestamp),
                    _remainingSeconds(localFromTimestamp)
                );
                console.log(
                    "_calculateYield | - toTimestamp: %s (day: %s + seconds: %s)",
                    localToTimestamp,
                    _effectiveDay(localToTimestamp),
                    _remainingSeconds(localToTimestamp)
                );
            }

            result = new YieldResult[](1);
            result[0] = _compoundYield(
                localFromTimestamp,
                localToTimestamp,
                params.yieldRates[params.startIndex].value,
                params.initialBalance + params.initialAccruedYield,
                params.initialStreamYield
            );

            if (_debug) {
                console.log("");
                console.log("_calculateYield | Result:");
                console.log("_calculateYield | - firstDayYield: %s", result[0].firstDayYield);
                console.log("_calculateYield | - fullDaysYield: %s", result[0].fullDaysYield);
                console.log("_calculateYield | - lastDayYield: %s", result[0].lastDayYield);
            }
        } else if (ratePeriods == 2) {
            /**
             * Scenario 2
             * If there are two yield rate periods in the range, we:
             * 1. Use the first yield rate to calculate the yield from `fromTimestamp` to the start of the second yield rate period.
             * 2. Use the second yield rate to calculate the yield from the start of the second yield rate period to `toTimestamp`.
             */

            if (_debug) {
                console.log("");
                console.log(" _calculateYield | Scenario 2: Two yield rates in range");
            }

            result = new YieldResult[](2);
            localFromTimestamp = params.fromTimestamp;
            localToTimestamp = params.yieldRates[params.startIndex + 1].effectiveDay * 1 days;

            if (_debug) {
                console.log("");
                console.log(" _calculateYield | Calculating yield for first period:");
                console.log(" _calculateYield | - yieldRate: %s", params.yieldRates[params.startIndex].value);
                console.log(
                    " _calculateYield | - fromTimestamp: %s (day: %s + seconds: %s)",
                    localFromTimestamp,
                    _effectiveDay(localFromTimestamp),
                    _remainingSeconds(localFromTimestamp)
                );
                console.log(
                    " _calculateYield | - localToTimestamp: %s (day: %s + seconds: %s)",
                    localToTimestamp,
                    _effectiveDay(localToTimestamp),
                    _remainingSeconds(localToTimestamp)
                );
            }

            result[0] = _compoundYield(
                localFromTimestamp,
                localToTimestamp,
                params.yieldRates[params.startIndex].value,
                params.initialBalance + params.initialAccruedYield,
                params.initialStreamYield
            );

            if (_debug) {
                console.log("");
                console.log("_calculateYield | Result:");
                console.log("_calculateYield | - firstDayYield: %s", result[0].firstDayYield);
                console.log("_calculateYield | - fullDaysYield: %s", result[0].fullDaysYield);
                console.log("_calculateYield | - lastDayYield: %s", result[0].lastDayYield);
            }

            localFromTimestamp = localToTimestamp;
            localToTimestamp = params.toTimestamp;

            if (_debug) {
                console.log("");
                console.log(" _calculateYield | Calculating yield for second period:");
                console.log(" _calculateYield | - yieldRate: %s", params.yieldRates[params.startIndex + 1].value);
                console.log(
                    " _calculateYield | - fromTimestamp: %s (day: %s + seconds: %s)",
                    localFromTimestamp,
                    _effectiveDay(localFromTimestamp),
                    _remainingSeconds(localFromTimestamp)
                );
                console.log(
                    " _calculateYield | - toTimestamp: %s (day: %s + seconds: %s)",
                    localToTimestamp,
                    _effectiveDay(localToTimestamp),
                    _remainingSeconds(localToTimestamp)
                );
            }

            result[1] = _compoundYield(
                localFromTimestamp,
                localToTimestamp,
                params.yieldRates[params.startIndex + 1].value,
                params.initialBalance +
                    params.initialAccruedYield +
                    result[0].firstDayYield +
                    result[0].fullDaysYield +
                    result[0].lastDayYield,
                0
            );

            if (_debug) {
                console.log("");
                console.log("_calculateYield | Result:");
                console.log("_calculateYield | - firstDayYield: %s", result[1].firstDayYield);
                console.log("_calculateYield | - fullDaysYield: %s", result[1].fullDaysYield);
                console.log("_calculateYield | - lastDayYield: %s", result[1].lastDayYield);
            }
        } else {
            /**
             * Scenario 3
             * If there are more than two yield rate periods in the range, we:
             * 1. Use the first yield rate to calculate the yield from `fromTimestamp` to the start of the second yield rate period.
             * 2. Use the second yield rate to calculate the yield from the start of the second yield rate period to the start of the third yield rate period.
             * 3. Repeat this process for each subsequent yield rate period until the last yield rate period.
             * 4. Use the last yield rate to calculate the yield from the start of the last yield rate period to `toTimestamp`.
             */

            if (_debug) {
                console.log("");
                console.log(" _calculateYield | Scenario 3: More than two yield rates in range");
            }

            uint256 currentBalance = params.initialBalance + params.initialAccruedYield;
            result = new YieldResult[](ratePeriods);
            localFromTimestamp = params.fromTimestamp;
            localToTimestamp = params.yieldRates[params.startIndex + 1].effectiveDay * 1 days;

            // Calculate yield for the first period

            if (_debug) {
                console.log("");
                console.log(" _calculateYield | Calculating yield for first period:");
                console.log(" _calculateYield | - yieldRate: %s", params.yieldRates[params.startIndex].value);
                console.log(
                    " _calculateYield | - fromTimestamp: %s (day: %s + seconds: %s)",
                    localFromTimestamp,
                    _effectiveDay(localFromTimestamp),
                    _remainingSeconds(localFromTimestamp)
                );
                console.log(
                    " _calculateYield | - localToTimestamp: %s (day: %s + seconds: %s)",
                    localToTimestamp,
                    _effectiveDay(localToTimestamp),
                    _remainingSeconds(localToTimestamp)
                );
            }

            result[0] = _compoundYield(
                localFromTimestamp,
                localToTimestamp,
                params.yieldRates[params.startIndex].value,
                currentBalance,
                params.initialStreamYield
            );

            if (_debug) {
                console.log("");
                console.log("_calculateYield | First period result:");
                console.log("_calculateYield | - firstDayYield: %s", result[0].firstDayYield);
                console.log("_calculateYield | - fullDaysYield: %s", result[0].fullDaysYield);
                console.log("_calculateYield | - lastDayYield: %s", result[0].lastDayYield);
            }

            currentBalance += result[0].firstDayYield + result[0].fullDaysYield + result[0].lastDayYield;

            // Calculate yield for the intermediate periods

            console.log("");
            console.log(" _calculateYield | Calculating yield for full %s periods:", ratePeriods - 2);

            for (uint256 i = params.startIndex + 1; i < params.startIndex + ratePeriods - 1; i++) {
                localFromTimestamp = params.yieldRates[i].effectiveDay * 1 days;
                localToTimestamp = params.yieldRates[i + 1].effectiveDay * 1 days;

                if (_debug) {
                    console.log("");
                    console.log(" _calculateYield | Period #%s:", i);
                    console.log(" _calculateYield | - yieldRate: %s", params.yieldRates[i].value);
                    console.log(
                        "_calculateYield | - fromTimestamp: %s (day: %s + seconds: %s)",
                        localFromTimestamp,
                        _effectiveDay(localFromTimestamp),
                        _remainingSeconds(localFromTimestamp)
                    );
                    console.log(
                        "_calculateYield | - toTimestamp: %s (day: %s + seconds: %s)",
                        localToTimestamp,
                        _effectiveDay(localToTimestamp),
                        _remainingSeconds(localToTimestamp)
                    );
                }

                result[i - params.startIndex] = _compoundYield(
                    localFromTimestamp,
                    localToTimestamp,
                    params.yieldRates[i].value,
                    currentBalance,
                    0
                );

                if (_debug) {
                    console.log("");
                    console.log("_calculateYield | Full period result: %s", i);
                    console.log("_calculateYield | - firstDayYield: %s", result[i - params.startIndex].firstDayYield);
                    console.log("_calculateYield | - fullDaysYield: %s", result[i - params.startIndex].fullDaysYield);
                    console.log("_calculateYield | - lastDayYield: %s", result[i - params.startIndex].lastDayYield);
                }

                currentBalance +=
                    result[i - params.startIndex].firstDayYield +
                    result[i - params.startIndex].fullDaysYield +
                    result[i - params.startIndex].lastDayYield;
            }

            // Calculate yield for the last period

            localFromTimestamp = params.yieldRates[params.startIndex + ratePeriods - 1].effectiveDay * 1 days;
            localToTimestamp = params.toTimestamp;

            if (_debug) {
                console.log("");
                console.log(" _calculateYield | - Calculating yield for last period:");
                console.log(
                    " _calculateYield | -- yieldRate: %s",
                    params.yieldRates[params.startIndex + ratePeriods - 1].value
                );
                console.log(
                    " _calculateYield | -- fromTimestamp: %s (day: %s + seconds: %s)",
                    localFromTimestamp,
                    _effectiveDay(localFromTimestamp),
                    _remainingSeconds(localFromTimestamp)
                );
                console.log(
                    " _calculateYield | -- toTimestamp: %s (day: %s + seconds: %s)",
                    localToTimestamp,
                    _effectiveDay(localToTimestamp),
                    _remainingSeconds(localToTimestamp)
                );
            }

            result[ratePeriods - 1] = _compoundYield(
                localFromTimestamp,
                localToTimestamp,
                params.yieldRates[params.startIndex + ratePeriods - 1].value,
                currentBalance,
                0
            );

            if (_debug) {
                console.log("");
                console.log("_calculateYield | Last period result:");
                console.log("_calculateYield | - firstDayYield: %s", result[ratePeriods - 1].firstDayYield);
                console.log("_calculateYield | - fullDaysYield: %s", result[ratePeriods - 1].fullDaysYield);
                console.log("_calculateYield | - lastDayYield: %s", result[ratePeriods - 1].lastDayYield);
            }
        }

        if (_debug) {
            console.log("");
            console.log(" _calculateYield | END");
        }

        return result;
    }

    function _inRangeYieldRates(
        YieldRate[] storage yieldRates,
        uint256 fromTimestamp,
        uint256 toTimestamp
    ) internal view returns (YieldRate[] memory inRangeYieldRates, uint256 inRangeStartIndex) {
        bool _debug = true;

        if (_debug) {
            console.log("");
            console.log("_inRangeYieldRates | START");
            console.log("_inRangeYieldRates | Getting yield rates from %s to %s", fromTimestamp, toTimestamp);

            console.log("");
            console.log("_inRangeYieldRates | Input yield rates:");
            for (uint256 i = 0; i < yieldRates.length; i++) {
                console.log(
                    "_inRangeYieldRates | - [%s] day: %s, rate: %s",
                    i,
                    yieldRates[i].effectiveDay,
                    yieldRates[i].value
                );
            }

            console.log("");
            console.log("_inRangeYieldRates | Starting loop:");
        }

        inRangeYieldRates = new YieldRate[](yieldRates.length);
        inRangeStartIndex = yieldRates.length;
        uint256 y = yieldRates.length;

        do {
            y--;

            if (_debug) {
                console.log("_inRangeYieldRates | - iteration: %s", y);
            }

            if (yieldRates[y].effectiveDay * 1 days >= toTimestamp) {
                if (_debug) {
                    console.log(
                        "-- _inRangeYieldRates | loop continue: effectiveDay >= toTimestamp: %s >= %s",
                        yieldRates[y].effectiveDay,
                        toTimestamp
                    );
                }
                continue;
            }

            inRangeStartIndex--;
            inRangeYieldRates[inRangeStartIndex] = yieldRates[y];

            if (_debug) {
                console.log(
                    "--  _inRangeYieldRates | loop insert: effectiveDay=%s, value=%s",
                    inRangeYieldRates[inRangeStartIndex].effectiveDay,
                    inRangeYieldRates[inRangeStartIndex].value
                );
            }

            if (yieldRates[y].effectiveDay * 1 days < fromTimestamp) {
                if (_debug) {
                    console.log(
                        "--  _inRangeYieldRates | loop break: effectiveDay < fromTimestamp: %s < %s",
                        yieldRates[y].effectiveDay,
                        fromTimestamp
                    );
                }
                break;
            }
        } while (y > 0);

        if (_debug) {
            console.log("");
            console.log("_accrueYield | In range yield rates:");
            for (uint256 i = inRangeStartIndex; i < inRangeYieldRates.length; i++) {
                console.log(
                    "-- [%s] day: %s, rate: %s",
                    i,
                    inRangeYieldRates[i].effectiveDay,
                    inRangeYieldRates[i].value
                );
            }

            console.log("");
            console.log("_inRangeYieldRates | END");
        }
    }

    // -------------------- Yield math -------------------- //

    function _calculatePartDayYield(
        uint256 amount,
        uint256 yieldRate,
        uint256 elapsedSeconds
    ) internal pure returns (uint256) {
        return (amount * yieldRate * elapsedSeconds) / (1 days * RATE_FACTOR);
    }

    function _calculateFullDayYield(
        uint256 amount, // Format: prevent collapse
        uint256 yieldRate
    ) internal pure returns (uint256) {
        return (amount * yieldRate) / RATE_FACTOR;
    }

    function _aggregateYield(
        YieldResult[] memory yieldResults
    ) internal pure returns (uint256 accruedYield, uint256 streamYield) {
        bool _debug = true;

        if (_debug) {
            console.log("");
        }

        if (yieldResults.length > 1) {
            if (_debug) {
                console.log("_aggregateYield | accruedYield: %s += %s", accruedYield, yieldResults[0].lastDayYield);
            }
            accruedYield += yieldResults[0].lastDayYield;
        }

        for (uint256 i = 0; i < yieldResults.length; i++) {
            if (_debug) {
                console.log(
                    "_aggregateYield | accruedYield: %s += %s + %s",
                    accruedYield,
                    yieldResults[i].firstDayYield,
                    yieldResults[i].fullDaysYield
                );
            }
            accruedYield += yieldResults[i].firstDayYield + yieldResults[i].fullDaysYield;
        }

        streamYield = yieldResults[yieldResults.length - 1].lastDayYield;
    }

    function _truncateArray(
        YieldRate[] memory array,
        uint256 startIndex
    ) internal pure returns (YieldRate[] memory truncatedArray) {
        truncatedArray = new YieldRate[](array.length - startIndex);
        for (uint256 i = startIndex; i < array.length; i++) {
            truncatedArray[i - startIndex] = array[i];
        }
    }

    // -------------------- Timestamp -------------------- //

    function _nextDay(uint256 timestamp) internal pure returns (uint256) {
        return timestamp - (timestamp % 1 days) + 1 days;
    }

    function _effectiveDay(uint256 timestamp) internal pure returns (uint256) {
        return timestamp / 1 days;
    }

    function _remainingSeconds(uint256 timestamp) internal pure returns (uint256) {
        return timestamp % 1 days;
    }

    function _effectiveTimestamp(uint256 timestamp) internal pure returns (uint256) {
        return (timestamp / 1 days) * 1 days;
    }

    function _blockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp - NEGATIVE_TIME_SHIFT;
    }

    // -------------------- Service -------------------- //

    function deposit(address account, uint256 amount) external {
        _increaseTokenBalance(account, amount);
    }

    function withdraw(address account, uint256 amount) external {
        _decreaseTokenBalance(account, amount);
    }
}
