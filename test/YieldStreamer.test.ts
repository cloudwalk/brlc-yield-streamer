import { ethers, network, upgrades } from "hardhat";
import { expect } from "chai";
import { BigNumber, Contract, ContractFactory } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { getTxTimestamp, proveTx } from "../test-utils/eth";
import { TransactionResponse } from "@ethersproject/abstract-provider";

const ZERO_ADDRESS = ethers.constants.AddressZero;
const BIG_NUMBER_ZERO = ethers.constants.Zero;
const BIG_NUMBER_MAX_UINT256 = ethers.constants.MaxUint256;
const YIELD_STREAMER_INIT_TOKEN_BALANCE: BigNumber = BigNumber.from(1000_000_000_000);
const USER_CURRENT_TOKEN_BALANCE: BigNumber = BigNumber.from(100_000_000_000);
const LOOK_BACK_PERIOD_LENGTH: number = 2;
const LOOK_BACK_PERIOD_INDEX_ZERO = 0;
const INITIAL_YIELD_RATE = 10000000000; // 1%
const BALANCE_TRACKER_INIT_DAY = 100;
const YIELD_STREAMER_INIT_DAY = BALANCE_TRACKER_INIT_DAY + LOOK_BACK_PERIOD_LENGTH - 1;
const YIELD_RATE_INDEX_ZERO = 0;
const FEE_RATE: BigNumber = BigNumber.from(0);
const RATE_FACTOR: BigNumber = BigNumber.from(1000000000000);
const MIN_CLAIM_AMOUNT: BigNumber = BigNumber.from(10000);
const MAX_DAILY_BALANCE_LIMIT: BigNumber = BigNumber.from(200_000_000_000);
const ROUNDING_COEF: BigNumber = BigNumber.from(10000);
const BALANCE_TRACKER_ADDRESS_STUB = "0x0000000000000000000000000000000000000001";
const ZERO_GROUP_ID = ethers.utils.formatBytes32String("");
const GROUP_ONE_ID = ethers.utils.formatBytes32String("GROUP_ONE");
const TIME_SHIFT_IN_SECONDS = -3 * 60 * 60;

interface TestContext {
  tokenMock: Contract;
  balanceTrackerMock: Contract;
  yieldStreamer: Contract;
}

interface BalanceRecord {
  day: number;
  value: BigNumber;
}

interface ClaimResult {
  nextClaimDay: BigNumber;
  nextClaimDebit: BigNumber;
  firstYieldDay: BigNumber;
  prevClaimDebit: BigNumber;
  primaryYield: BigNumber;
  streamYield: BigNumber;
  lastDayYield: BigNumber;
  shortfall: BigNumber;
  fee: BigNumber;
  yield: BigNumber;
  claimDebitIsGreaterThanFirstDayYield: boolean;
}

interface LookBackPeriodRecord {
  effectiveDay: number;
  length: BigNumber;
}

interface YieldRateRecord {
  effectiveDay: number;
  value: BigNumber;
}

interface ClaimRequest {
  amount: BigNumber;
  firstYieldDay: number;
  claimDay: number;
  claimTime: number;
  claimDebit: BigNumber;
  lookBackPeriodLength: number;
  yieldRateRecords: YieldRateRecord[];
  balanceRecords: BalanceRecord[];
}

interface YieldByDaysRequest {
  lookBackPeriodLength: number;
  yieldRateRecords: YieldRateRecord[];
  balanceRecords: BalanceRecord[];
  dayFrom: number;
  dayTo: number;
  claimDebit: BigNumber;
}

interface BalanceWithYieldByDaysRequest extends YieldByDaysRequest {
  firstYieldDay: number;
}

interface ClaimState {
  day: number;
  debit: BigNumber;
}

interface Version {
  major: number;
  minor: number;
  patch: number;

  [key: string]: number; // Indexing signature to ensure that fields are iterated over in a key-value style
}

const balanceRecordsCase1: BalanceRecord[] = [
  { day: BALANCE_TRACKER_INIT_DAY, value: BigNumber.from(0) },
  { day: BALANCE_TRACKER_INIT_DAY + 1, value: BigNumber.from(80_000_000_000) },
  { day: BALANCE_TRACKER_INIT_DAY + 2, value: BigNumber.from(70_000_000_000) },
  { day: BALANCE_TRACKER_INIT_DAY + 3, value: BigNumber.from(60_000_000_000) },
  { day: BALANCE_TRACKER_INIT_DAY + 4, value: BigNumber.from(50_000_000_000) },
  { day: BALANCE_TRACKER_INIT_DAY + 5, value: BigNumber.from(10_000_000_000) },
  { day: BALANCE_TRACKER_INIT_DAY + 6, value: BigNumber.from(30_000_000_000) },
  { day: BALANCE_TRACKER_INIT_DAY + 7, value: BigNumber.from(20_000_000_000) },
  { day: BALANCE_TRACKER_INIT_DAY + 8, value: BigNumber.from(10_000_000_000) }
];

const yieldRateRecordCase1: YieldRateRecord = {
  effectiveDay: YIELD_STREAMER_INIT_DAY,
  value: BigNumber.from(INITIAL_YIELD_RATE)
};

const yieldRateRecordCase2: YieldRateRecord = {
  effectiveDay: YIELD_STREAMER_INIT_DAY + 4,
  value: BigNumber.from(INITIAL_YIELD_RATE * 2)
};

const yieldRateRecordCase3: YieldRateRecord = {
  effectiveDay: YIELD_STREAMER_INIT_DAY + 6,
  value: BigNumber.from(INITIAL_YIELD_RATE * 3)
};

const EXPECTED_VERSION: Version = {
  major: 1,
  minor: 3,
  patch: 0
};

const EMPTY_CLAIM_RESULT: ClaimResult = {
  nextClaimDay: BigNumber.from(0),
  nextClaimDebit: BigNumber.from(0),
  firstYieldDay: BigNumber.from(0),
  prevClaimDebit: BigNumber.from(0),
  primaryYield: BigNumber.from(0),
  streamYield: BigNumber.from(0),
  lastDayYield: BigNumber.from(0),
  shortfall: BigNumber.from(0),
  fee: BigNumber.from(0),
  yield: BigNumber.from(0),
  claimDebitIsGreaterThanFirstDayYield: false
};

function defineExpectedDailyBalances(balanceRecords: BalanceRecord[], dayFrom: number, dayTo: number): BigNumber[] {
  if (dayFrom > dayTo) {
    throw new Error(
      `Cannot define daily balances because 'dayFrom' is greater than 'dayTo'. ` +
      `The 'dayFrom' value: ${dayFrom}. The 'dayTo' value: ${dayTo}`
    );
  }
  const dailyBalances: BigNumber[] = [];
  if (balanceRecords.length === 0) {
    for (let day = dayFrom; day <= dayTo; ++day) {
      dailyBalances.push(USER_CURRENT_TOKEN_BALANCE);
    }
  } else {
    let recordIndex = 0;
    for (let day = dayFrom; day <= dayTo; ++day) {
      for (; recordIndex < balanceRecords.length; ++recordIndex) {
        if (balanceRecords[recordIndex].day >= day) {
          break;
        }
      }
      if (recordIndex >= balanceRecords.length || balanceRecords[recordIndex].day < day) {
        dailyBalances.push(USER_CURRENT_TOKEN_BALANCE);
      } else {
        dailyBalances.push(balanceRecords[recordIndex].value);
      }
    }
  }
  return dailyBalances;
}

function defineDailyBalance(bigNumber1: BigNumber, bigNumber2: BigNumber): BigNumber {
  let res: BigNumber;
  if (bigNumber1.lt(bigNumber2)) {
    res = bigNumber1;
  } else {
    res = bigNumber2;
  }

  if (res.gt(MAX_DAILY_BALANCE_LIMIT)) {
    res = MAX_DAILY_BALANCE_LIMIT;
  }

  return res;
}

function roundDown(value: BigNumber): BigNumber {
  return value.div(ROUNDING_COEF).mul(ROUNDING_COEF);
}

function roundUpward(value: BigNumber): BigNumber {
  let roundedValue = value.div(ROUNDING_COEF).mul(ROUNDING_COEF);
  if (!roundedValue.eq(value)) {
    roundedValue = roundedValue.add(ROUNDING_COEF);
  }
  return roundedValue;
}

function defineYieldRate(yieldRateRecords: YieldRateRecord[], day: number): BigNumber {
  const len = yieldRateRecords.length;
  if (len === 0) {
    return BIG_NUMBER_ZERO;
  }
  if (yieldRateRecords[0].effectiveDay > day) {
    return BIG_NUMBER_ZERO;
  }

  for (let i = 0; i < len; ++i) {
    const yieldRateRecord: YieldRateRecord = yieldRateRecords[i];
    if (yieldRateRecord.effectiveDay > day) {
      return yieldRateRecords[i - 1].value;
    }
  }

  return yieldRateRecords[yieldRateRecords.length - 1].value;
}

function defineExpectedYieldByDays(yieldByDaysRequest: YieldByDaysRequest): BigNumber[] {
  const { lookBackPeriodLength, yieldRateRecords, balanceRecords, dayFrom, dayTo, claimDebit } = yieldByDaysRequest;
  if (dayFrom > dayTo) {
    throw new Error("Day 'from' is grater than day 'to' when defining the yield by days");
  }
  const len = dayTo + 1 - dayFrom;
  const yieldByDays: BigNumber[] = [];
  const balancesDayFrom = dayFrom - lookBackPeriodLength + 1;
  const balancesDayTo = dayTo + 1;
  const balances: BigNumber[] = defineExpectedDailyBalances(balanceRecords, balancesDayFrom, balancesDayTo);

  let sumYield: BigNumber = BIG_NUMBER_ZERO;
  for (let i = 0; i < len; ++i) {
    const yieldRate: BigNumber = defineYieldRate(yieldRateRecords, dayFrom + i);
    const minBalance: BigNumber = balances.slice(i, lookBackPeriodLength + i).reduce(defineDailyBalance);
    const yieldValue: BigNumber = minBalance.mul(yieldRate).div(RATE_FACTOR);
    if (i == 0) {
      if (yieldValue.gt(claimDebit)) {
        sumYield = yieldValue.sub(claimDebit);
      }
    } else {
      sumYield = sumYield.add(yieldValue);
    }
    balances[lookBackPeriodLength + i] = balances[lookBackPeriodLength + i].add(sumYield);
    yieldByDays.push(yieldValue);
  }

  return yieldByDays;
}

function defineExpectedBalanceWithYieldByDays(request: BalanceWithYieldByDaysRequest): BigNumber[] {
  const { balanceRecords, dayFrom, dayTo, firstYieldDay } = request;
  const balancesWithYield: BigNumber[] = defineExpectedDailyBalances(balanceRecords, dayFrom, dayTo);
  if (firstYieldDay <= dayTo) {
    const yieldByDaysRequest: YieldByDaysRequest = { ...(request as YieldByDaysRequest) };
    yieldByDaysRequest.dayFrom = request.firstYieldDay;
    const yields: BigNumber[] = defineExpectedYieldByDays(yieldByDaysRequest);
    if (yields[0].gt(request.claimDebit)) {
      yields[0] = yields[0].sub(request.claimDebit);
    } else {
      yields[0] = BIG_NUMBER_ZERO;
    }

    let sumYield = BIG_NUMBER_ZERO;
    for (let i = 0; i < balancesWithYield.length; ++i) {
      const yieldIndex = i + dayFrom - firstYieldDay - 1;
      if (yieldIndex >= 0) {
        sumYield = sumYield.add(yields[yieldIndex]);
        balancesWithYield[i] = balancesWithYield[i].add(sumYield);
      }
    }
  }

  return balancesWithYield;
}

function calculateFee(amount: BigNumber): BigNumber {
  return roundUpward(amount.mul(FEE_RATE).div(RATE_FACTOR));
}

function defineExpectedClaimResult(claimRequest: ClaimRequest): ClaimResult {
  const dayFrom: number = claimRequest.firstYieldDay;
  const dayTo: number = claimRequest.claimDay - 1;
  const yieldByDays: BigNumber[] = defineExpectedYieldByDays({
    lookBackPeriodLength: claimRequest.lookBackPeriodLength,
    yieldRateRecords: claimRequest.yieldRateRecords,
    balanceRecords: claimRequest.balanceRecords,
    dayFrom,
    dayTo,
    claimDebit: claimRequest.claimDebit
  });

  const lastIndex = yieldByDays.length - 1;
  const lastYield = yieldByDays[lastIndex];
  const partialLastYield: BigNumber = lastYield.mul(claimRequest.claimTime).div(86400);
  let indexWhenPrimaryYieldReachedAmount = lastIndex;
  let valueWhenPrimaryYieldReachedAmount: BigNumber = BIG_NUMBER_ZERO;
  let primaryYieldReachedAmount = false;
  let claimDebitIsGreaterThanFirstDayYield = false;

  if (dayFrom !== dayTo) {
    if (yieldByDays[0].gte(claimRequest.claimDebit)) {
      yieldByDays[0] = yieldByDays[0].sub(claimRequest.claimDebit);
    } else {
      yieldByDays[0] = BIG_NUMBER_ZERO;
      claimDebitIsGreaterThanFirstDayYield = true;
    }
  }

  let primaryYield = BIG_NUMBER_ZERO;
  for (let i = 0; i < lastIndex; ++i) {
    const yieldValue = yieldByDays[i];
    primaryYield = primaryYield.add(yieldValue);
    if (!primaryYieldReachedAmount) {
      if (primaryYield.gte(claimRequest.amount)) {
        indexWhenPrimaryYieldReachedAmount = i;
        valueWhenPrimaryYieldReachedAmount = primaryYield;
        primaryYieldReachedAmount = true;
      }
    }
  }

  let nextClaimDay: number;
  let nextClaimDebit: BigNumber;
  let streamYield: BigNumber;
  if (dayFrom === dayTo) {
    if (partialLastYield.gte(claimRequest.claimDebit)) {
      streamYield = partialLastYield.sub(claimRequest.claimDebit);
    } else {
      streamYield = BIG_NUMBER_ZERO;
      claimDebitIsGreaterThanFirstDayYield = true;
    }
    nextClaimDay = dayTo;
    if (claimRequest.amount.gt(streamYield)) {
      nextClaimDebit = claimRequest.claimDebit.add(streamYield);
    } else {
      nextClaimDebit = claimRequest.claimDebit.add(claimRequest.amount);
    }
  } else {
    streamYield = partialLastYield;
    if (primaryYieldReachedAmount) {
      nextClaimDay = dayFrom + indexWhenPrimaryYieldReachedAmount;
      const yieldSurplus: BigNumber = valueWhenPrimaryYieldReachedAmount.sub(claimRequest.amount);
      nextClaimDebit = yieldByDays[indexWhenPrimaryYieldReachedAmount].sub(yieldSurplus);
      if (indexWhenPrimaryYieldReachedAmount === 0) {
        nextClaimDebit = nextClaimDebit.add(claimRequest.claimDebit);
      }
    } else {
      nextClaimDay = dayTo;
      const amountSurplus: BigNumber = claimRequest.amount.sub(primaryYield);
      if (partialLastYield.gt(amountSurplus)) {
        nextClaimDebit = amountSurplus;
      } else {
        nextClaimDebit = partialLastYield;
      }
    }
  }

  let totalYield = primaryYield.add(streamYield);
  let shortfall: BigNumber = BIG_NUMBER_ZERO;
  if (claimRequest.amount.lt(BIG_NUMBER_MAX_UINT256)) {
    if (claimRequest.amount.gt(totalYield)) {
      shortfall = claimRequest.amount.sub(totalYield);
      totalYield = BIG_NUMBER_ZERO;
    } else {
      totalYield = claimRequest.amount;
    }
  } else {
    totalYield = roundDown(totalYield);
  }
  const fee: BigNumber = calculateFee(totalYield);

  return {
    nextClaimDay: BigNumber.from(nextClaimDay),
    nextClaimDebit: nextClaimDebit,
    firstYieldDay: BigNumber.from(dayFrom),
    prevClaimDebit: claimRequest.claimDebit,
    streamYield,
    primaryYield,
    lastDayYield: lastYield,
    shortfall,
    fee,
    yield: totalYield,
    claimDebitIsGreaterThanFirstDayYield
  };
}

function defineExpectedClaimAllResult(claimRequest: ClaimRequest): ClaimResult {
  const previousAmount = claimRequest.amount;
  claimRequest.amount = BIG_NUMBER_MAX_UINT256;
  const claimResult = defineExpectedClaimResult(claimRequest);
  claimRequest.amount = previousAmount;
  return claimResult;
}

function compareClaimPreviews(actualClaimPreviewResult: ClaimResult, expectedClaimPreviewResult: ClaimResult) {
  expect(actualClaimPreviewResult.nextClaimDay.toString()).to.equal(
    expectedClaimPreviewResult.nextClaimDay.toString(),
    "The 'nextClaimDay' field is wrong"
  );

  expect(actualClaimPreviewResult.nextClaimDebit.toString()).to.equal(
    expectedClaimPreviewResult.nextClaimDebit.toString(),
    "The 'nextClaimDebit' field is wrong"
  );

  expect(actualClaimPreviewResult.primaryYield.toString()).to.equal(
    expectedClaimPreviewResult.primaryYield.toString(),
    "The 'nextClaimDebit' field is wrong"
  );

  expect(actualClaimPreviewResult.streamYield.toString()).to.equal(
    expectedClaimPreviewResult.streamYield.toString(),
    "The 'streamYield' field is wrong"
  );

  expect(actualClaimPreviewResult.shortfall.toString()).to.equal(
    expectedClaimPreviewResult.shortfall.toString(),
    "The 'shortfall' field is wrong"
  );

  expect(actualClaimPreviewResult.fee.toString()).to.equal(
    expectedClaimPreviewResult.fee.toString(),
    "The 'fee' field is wrong"
  );

  expect(actualClaimPreviewResult.yield.toString()).to.equal(
    expectedClaimPreviewResult.yield.toString(),
    "The 'yield' field is wrong"
  );
}

async function checkLookBackPeriods(yieldStreamer: Contract, expectedLookBackPeriodRecords: LookBackPeriodRecord[]) {
  const expectedRecordArrayLength = expectedLookBackPeriodRecords.length;
  const actualRecordState = await yieldStreamer.getLookBackPeriods();
  const actualRecordArrayLength: number = actualRecordState.length;

  expect(actualRecordArrayLength).to.equal(
    expectedRecordArrayLength,
    `Wrong look-back period array length`
  );

  for (let i = 0; i < expectedRecordArrayLength; i++) {
    const expectedRecord: LookBackPeriodRecord = expectedLookBackPeriodRecords[i];

    expect(actualRecordState[i].length).to.equal(
      2,
      `Wrong look-back structure: expected 2 elements in array`
    );

    const actualRecord: LookBackPeriodRecord = {
      effectiveDay: actualRecordState[i][0],
      length: BigNumber.from(actualRecordState[i][1])
    };

    expect(actualRecord.effectiveDay).to.equal(
      expectedRecord.effectiveDay,
      `Wrong field '_lookBackPeriods[${i}].effectiveDay'`
    );
    expect(actualRecord.length).to.equal(
      expectedRecord.length,
      `Wrong field '_lookBackPeriods[${i}].length'`
    );
  }
}

async function checkYieldRates(
  yieldStreamer: Contract,
  expectedYieldRateRecords: YieldRateRecord[],
  groupId: string
) {
  const actualYieldRateRecords = await yieldStreamer.getGroupYieldRates(groupId);
  const expectedRecordArrayLength = expectedYieldRateRecords.length;
  const actualRecordArrayLength: number = actualYieldRateRecords.length;
  expect(actualRecordArrayLength).to.equal(
    expectedRecordArrayLength,
    `Wrong yield rate array length for the account group with ID: ${groupId}`
  );

  for (let i = 0; i < expectedRecordArrayLength; i++) {
    const expectedRecord: YieldRateRecord = expectedYieldRateRecords[i];

    expect(actualYieldRateRecords[i].length).to.equal(
      2,
      `Wrong yield rate record structure for _yieldRates[${groupId}][${i}]: expected 2 elements in array`
    );

    const actualRecord: YieldRateRecord = {
      effectiveDay: actualYieldRateRecords[i][0],
      value: BigNumber.from(actualYieldRateRecords[i][1])
    };

    expect(actualRecord.effectiveDay).to.equal(
      expectedRecord.effectiveDay,
      `Wrong field '_yieldRates[${groupId}][${i}].effectiveDay'`
    );
    expect(actualRecord.value).to.equal(
      expectedRecord.value,
      `Wrong field '_yieldRates[${groupId}][${i}].length'`
    );
  }
}

async function setUpFixture<T>(func: () => Promise<T>): Promise<T> {
  if (network.name === "hardhat") {
    return loadFixture(func);
  } else {
    return func();
  }
}

function defineExpectedYieldRateRecords(): YieldRateRecord[] {
  const expectedYieldRateRecord1: YieldRateRecord = {
    effectiveDay: YIELD_STREAMER_INIT_DAY,
    value: BigNumber.from(INITIAL_YIELD_RATE)
  };
  const expectedYieldRateRecord2: YieldRateRecord = {
    effectiveDay: YIELD_STREAMER_INIT_DAY + 3,
    value: BigNumber.from(INITIAL_YIELD_RATE * 2)
  };
  const expectedYieldRateRecord3: YieldRateRecord = {
    effectiveDay: YIELD_STREAMER_INIT_DAY + 6,
    value: BigNumber.from(INITIAL_YIELD_RATE * 3)
  };

  return [expectedYieldRateRecord1, expectedYieldRateRecord2, expectedYieldRateRecord3];
}

describe("Contract 'YieldStreamer'", async () => {
  const REVERT_MESSAGE_INITIALIZABLE_CONTRACT_IS_ALREADY_INITIALIZED = "Initializable: contract is already initialized";
  const REVERT_MESSAGE_OWNABLE_CALLER_IS_NOT_THE_OWNER = "Ownable: caller is not the owner";
  const REVERT_MESSAGE_PAUSABLE_PAUSED = "Pausable: paused";

  const REVERT_ERROR_BLOCKLISTED_ACCOUNT = "BlocklistedAccount";
  const REVERT_ERROR_BALANCE_TRACKER_ALREADY_CONFIGURED = "BalanceTrackerAlreadyConfigured";
  const REVERT_ERROR_CLAIM_AMOUNT_BELOW_MINIMUM = "ClaimAmountBelowMinimum";
  const REVERT_ERROR_CLAIM_AMOUNT_NON_ROUNDED = "ClaimAmountNonRounded";
  const REVERT_ERROR_CLAIM_REJECTION_DUE_TO_SHORTFALL = "ClaimRejectionDueToShortfall";
  const REVERT_ERROR_FEE_RECEIVER_ALREADY_CONFIGURED = "FeeReceiverAlreadyConfigured";
  const REVERT_ERROR_LOOK_BACK_PERIOD_COUNT_LIMIT = "LookBackPeriodCountLimit";
  const REVERT_ERROR_LOOK_BACK_PERIOD_WRONG_INDEX = "LookBackPeriodWrongIndex";
  const REVERT_ERROR_LOOK_BACK_PERIOD_INVALID_EFFECTIVE_DAY = "LookBackPeriodInvalidEffectiveDay";
  const REVERT_ERROR_LOOK_BACK_PERIOD_INVALID_PARAMETERS_COMBINATION = "LookBackPeriodInvalidParametersCombination";
  const REVERT_ERROR_LOOK_BACK_PERIOD_LENGTH_ALREADY_CONFIGURED = "LookBackPeriodLengthAlreadyConfigured";
  const REVERT_ERROR_LOOK_BACK_PERIOD_LENGTH_ZERO = "LookBackPeriodLengthZero";
  const REVERT_ERROR_SAFE_CAST_OVERFLOW_UINT16 = "SafeCastOverflowUint16";
  const REVERT_ERROR_SAFE_CAST_OVERFLOW_UINT240 = "SafeCastOverflowUint240";
  const REVERT_ERROR_TO_DAY_PRIOR_FROM_DAY = "ToDayPriorFromDay";
  const REVERT_ERROR_YIELD_RATE_INVALID_EFFECTIVE_DAY = "YieldRateInvalidEffectiveDay";
  const REVERT_ERROR_YIELD_RATE_VALUE_ALREADY_CONFIGURED = "YieldRateValueAlreadyConfigured";
  const REVERT_ERROR_YIELD_RATE_WRONG_INDEX = "YieldRateWrongIndex";
  const REVERT_ERROR_GROUP_ALREADY_ASSIGNED = "GroupAlreadyAssigned";
  const REVERT_ERROR_CALLER_NOT_BLOCKLISTER = "UnauthorizedBlocklister";

  const EVENT_BALANCE_TRACKER_CHANGED = "BalanceTrackerChanged";
  const EVENT_CLAIM = "Claim";
  const EVENT_FEE_RECEIVER_CHANGED = "FeeReceiverChanged";
  const EVENT_LOOK_BACK_PERIOD_CONFIGURED = "LookBackPeriodConfigured";
  const EVENT_LOOK_BACK_PERIOD_UPDATED = "LookBackPeriodUpdated";
  const EVENT_YIELD_RATE_CONFIGURED = "YieldRateConfigured";
  const EVENT_YIELD_RATE_UPDATED = "YieldRateUpdated";
  const EVENT_ACCOUNT_TO_GROUP_ASSIGNED = "AccountGroupAssigned";
  const EVENT_YIELD_STREAMING_STOPPED = "YieldStreamingStopped";

  let tokenMockFactory: ContractFactory;
  let balanceTrackerMockFactory: ContractFactory;
  let yieldStreamerFactory: ContractFactory;
  let deployer: SignerWithAddress;
  let user: SignerWithAddress;
  let user2: SignerWithAddress;
  let user3: SignerWithAddress;
  let blocklister: SignerWithAddress;
  let feeReceiver: SignerWithAddress;

  before(async () => {
    [deployer, user, feeReceiver, user2, user3, blocklister] = await ethers.getSigners();
    tokenMockFactory = await ethers.getContractFactory("ERC20TokenMock");
    balanceTrackerMockFactory = await ethers.getContractFactory("BalanceTrackerMock");
    yieldStreamerFactory = await ethers.getContractFactory("YieldStreamerTestable");
  });

  async function deployContracts(): Promise<TestContext> {
    const tokenMock: Contract = await upgrades.deployProxy(tokenMockFactory, ["Test Token Mock", "TTM"]);
    await tokenMock.deployed();

    const balanceTrackerMock: Contract = await balanceTrackerMockFactory.deploy(tokenMock.address);
    await balanceTrackerMock.deployed();

    const yieldStreamer: Contract = await upgrades.deployProxy(yieldStreamerFactory);
    await yieldStreamer.deployed();
    await proveTx(yieldStreamer.enableBlocklist(true));

    return {
      tokenMock,
      balanceTrackerMock,
      yieldStreamer
    };
  }

  async function deployAndConfigureContracts(): Promise<TestContext> {
    const { tokenMock, balanceTrackerMock, yieldStreamer } = await deployContracts();

    await proveTx(yieldStreamer.setFeeReceiver(feeReceiver.address));
    await proveTx(yieldStreamer.setBalanceTracker(balanceTrackerMock.address));
    await proveTx(yieldStreamer.configureYieldRate(ZERO_GROUP_ID, YIELD_STREAMER_INIT_DAY, INITIAL_YIELD_RATE));
    await proveTx(yieldStreamer.configureLookBackPeriod(YIELD_STREAMER_INIT_DAY, LOOK_BACK_PERIOD_LENGTH));
    await proveTx(balanceTrackerMock.setInitDay(BALANCE_TRACKER_INIT_DAY));
    await proveTx(balanceTrackerMock.setCurrentBalance(user.address, USER_CURRENT_TOKEN_BALANCE));
    await proveTx(tokenMock.mintForTest(yieldStreamer.address, YIELD_STREAMER_INIT_TOKEN_BALANCE));

    return {
      tokenMock,
      balanceTrackerMock,
      yieldStreamer
    };
  }

  describe("Test settings", async () => {
    it("All daily balances in test balance records are less than the yield-generating limit", async () => {
      for (const balanceRecord of balanceRecordsCase1) {
        expect(balanceRecord.value).to.be.lessThan(MAX_DAILY_BALANCE_LIMIT);
      }
    });
  });

  describe("Function 'initialize()'", async () => {
    it("Configures the contract as expected", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const { yieldStreamer } = context;
      expect(await yieldStreamer.owner()).to.equal(deployer.address);
      expect(await yieldStreamer.balanceTracker()).to.equal(ZERO_ADDRESS);
      expect(await yieldStreamer.feeReceiver()).to.equal(ZERO_ADDRESS);
      expect(await yieldStreamer.RATE_FACTOR()).to.equal(RATE_FACTOR);
      expect(await yieldStreamer.FEE_RATE()).to.equal(FEE_RATE);
      expect(await yieldStreamer.MIN_CLAIM_AMOUNT()).to.equal(MIN_CLAIM_AMOUNT);
      expect(await yieldStreamer.ROUNDING_COEF()).to.equal(ROUNDING_COEF);
      expect(await yieldStreamer.MAX_DAILY_BALANCE_LIMIT()).to.equal(MAX_DAILY_BALANCE_LIMIT);
      await checkLookBackPeriods(yieldStreamer, []);
      await checkYieldRates(yieldStreamer, [], ZERO_GROUP_ID);
    });

    it("Is reverted if called for the second time", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      await expect(
        context.yieldStreamer.initialize()
      ).to.be.revertedWith(REVERT_MESSAGE_INITIALIZABLE_CONTRACT_IS_ALREADY_INITIALIZED);
    });

    it("Is reverted if the implementation contract is called even for the first time", async () => {
      const yieldStreamerImplementation: Contract = await yieldStreamerFactory.deploy();
      await yieldStreamerImplementation.deployed();
      await expect(
        yieldStreamerImplementation.initialize()
      ).to.be.revertedWith(REVERT_MESSAGE_INITIALIZABLE_CONTRACT_IS_ALREADY_INITIALIZED);
    });
  });

  describe("Function '$__VERSION()'", async () => {
    it("Returns expected values", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const { yieldStreamer } = context;
      const yieldStreamerVersion = await yieldStreamer.$__VERSION();
      Object.keys(EXPECTED_VERSION).forEach(property => {
        const value = yieldStreamerVersion[property];
        if (typeof value === "undefined" || typeof value === "function" || typeof value === "object") {
          throw Error(`Property "${property}" is not found`);
        }
        expect(value).to.eq(
          EXPECTED_VERSION[property],
          `Mismatch in the "${property}" property`
        );
      });
    });
  });

  describe("Function 'setIsArchived()'", async () => {
    it("Can set the contract to archived state", async () => {
      const context: TestContext = await setUpFixture(deployAndConfigureContracts);

      expect(await context.yieldStreamer.isArchived()).to.equal(false);

      const tx = await context.yieldStreamer.setIsArchived(true);

      await expect(tx)
        .to.emit(context.yieldStreamer, "IsArchivedChanged")
        .withArgs(true);

      expect(await context.yieldStreamer.isArchived()).to.equal(true);
    });

    it("Can set the contract back to not archived state", async () => {
      const context: TestContext = await setUpFixture(deployAndConfigureContracts);

      await proveTx(context.yieldStreamer.setIsArchived(true));
      expect(await context.yieldStreamer.isArchived()).to.equal(true);

      const tx = await context.yieldStreamer.setIsArchived(false);

      await expect(tx)
        .to.emit(context.yieldStreamer, "IsArchivedChanged")
        .withArgs(false);

      expect(await context.yieldStreamer.isArchived()).to.equal(false);
    });

    it("Reverts when trying to archive an already archived contract", async () => {
      const context: TestContext = await setUpFixture(deployAndConfigureContracts);

      await proveTx(context.yieldStreamer.setIsArchived(true));

      await expect(context.yieldStreamer.setIsArchived(true))
        .to.be.revertedWithCustomError(context.yieldStreamer, "ContractAlreadyArchived");
    });

    it("Can only be called by the owner", async () => {
      const context: TestContext = await setUpFixture(deployAndConfigureContracts);

      await expect(context.yieldStreamer.connect(user).setIsArchived(true))
        .to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("Function 'setFeeReceiver()'", async () => {
    it("Executes as expected", async () => {
      const context: TestContext = await setUpFixture(deployContracts);

      await expect(context.yieldStreamer.setFeeReceiver(feeReceiver.address))
        .to.emit(context.yieldStreamer, EVENT_FEE_RECEIVER_CHANGED)
        .withArgs(feeReceiver.address, ZERO_ADDRESS);

      expect(await context.yieldStreamer.feeReceiver()).to.equal(feeReceiver.address);

      await expect(context.yieldStreamer.setFeeReceiver(ZERO_ADDRESS))
        .to.emit(context.yieldStreamer, EVENT_FEE_RECEIVER_CHANGED)
        .withArgs(ZERO_ADDRESS, feeReceiver.address);

      expect(await context.yieldStreamer.feeReceiver()).to.equal(ZERO_ADDRESS);
    });

    it("Is reverted if it is called not by the owner", async () => {
      const context: TestContext = await setUpFixture(deployContracts);

      await expect(
        context.yieldStreamer.connect(user).setFeeReceiver(feeReceiver.address)
      ).to.be.revertedWith(REVERT_MESSAGE_OWNABLE_CALLER_IS_NOT_THE_OWNER);
    });

    it("Is reverted if the same fee receiver is already configured", async () => {
      const context: TestContext = await setUpFixture(deployContracts);

      await expect(
        context.yieldStreamer.setFeeReceiver(ZERO_ADDRESS)
      ).to.be.revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_FEE_RECEIVER_ALREADY_CONFIGURED);

      await proveTx(context.yieldStreamer.setFeeReceiver(feeReceiver.address));

      await expect(
        context.yieldStreamer.setFeeReceiver(feeReceiver.address)
      ).to.be.revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_FEE_RECEIVER_ALREADY_CONFIGURED);
    });
  });

  describe("Function 'setBalanceTracker()'", async () => {
    it("Executes as expected", async () => {
      const context: TestContext = await setUpFixture(deployContracts);

      await expect(context.yieldStreamer.setBalanceTracker(BALANCE_TRACKER_ADDRESS_STUB))
        .to.emit(context.yieldStreamer, EVENT_BALANCE_TRACKER_CHANGED)
        .withArgs(BALANCE_TRACKER_ADDRESS_STUB, ZERO_ADDRESS);

      expect(await context.yieldStreamer.balanceTracker()).to.equal(BALANCE_TRACKER_ADDRESS_STUB);

      await expect(context.yieldStreamer.setBalanceTracker(ZERO_ADDRESS))
        .to.emit(context.yieldStreamer, EVENT_BALANCE_TRACKER_CHANGED)
        .withArgs(ZERO_ADDRESS, BALANCE_TRACKER_ADDRESS_STUB);

      expect(await context.yieldStreamer.balanceTracker()).to.equal(ZERO_ADDRESS);
    });

    it("Is reverted if it is called not by the owner", async () => {
      const context: TestContext = await setUpFixture(deployContracts);

      await expect(
        context.yieldStreamer.connect(user).setBalanceTracker(BALANCE_TRACKER_ADDRESS_STUB)
      ).to.be.revertedWith(REVERT_MESSAGE_OWNABLE_CALLER_IS_NOT_THE_OWNER);
    });

    it("Is reverted if the same balance tracker is already configured", async () => {
      const context: TestContext = await setUpFixture(deployContracts);

      await expect(
        context.yieldStreamer.setBalanceTracker(ZERO_ADDRESS)
      ).to.be.revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_BALANCE_TRACKER_ALREADY_CONFIGURED);

      await proveTx(context.yieldStreamer.setBalanceTracker(BALANCE_TRACKER_ADDRESS_STUB));

      await expect(
        context.yieldStreamer.setBalanceTracker(BALANCE_TRACKER_ADDRESS_STUB)
      ).to.be.revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_BALANCE_TRACKER_ALREADY_CONFIGURED);
    });
  });

  describe("Function 'assignAccountGroup()'", async () => {
    let users: string[];
    before(async () => {
      users = [user.address, user2.address, user3.address];
    });
    it("Executes as expected and emits the corresponding events", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      await proveTx(context.yieldStreamer.setMainBlocklister(blocklister.address));
      await expect(context.yieldStreamer.connect(blocklister).assignAccountGroup(GROUP_ONE_ID, users))
        .to.emit(context.yieldStreamer, EVENT_ACCOUNT_TO_GROUP_ASSIGNED)
        .withArgs(GROUP_ONE_ID, user.address)
        .and.to.emit(context.yieldStreamer, EVENT_ACCOUNT_TO_GROUP_ASSIGNED)
        .withArgs(GROUP_ONE_ID, user2.address)
        .and.to.emit(context.yieldStreamer, EVENT_ACCOUNT_TO_GROUP_ASSIGNED)
        .withArgs(GROUP_ONE_ID, user3.address);
      for (const userAddress of users) {
        expect(await context.yieldStreamer.getAccountGroup(userAddress)).to.equal(GROUP_ONE_ID);
      }
    });

    it("Is reverted if caller is not the blocklister", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      await expect(context.yieldStreamer.connect(user).assignAccountGroup(GROUP_ONE_ID, users))
        .to.be.revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_CALLER_NOT_BLOCKLISTER)
        .withArgs(user.address);
    });

    it("Is reverted if user is already assigned to group", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      await proveTx(context.yieldStreamer.setMainBlocklister(blocklister.address));
      await proveTx(context.yieldStreamer.connect(blocklister).assignAccountGroup(GROUP_ONE_ID, [user3.address]));
      await expect(context.yieldStreamer.connect(blocklister).assignAccountGroup(GROUP_ONE_ID, users))
        .to.be.revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_GROUP_ALREADY_ASSIGNED)
        .withArgs(user3.address);
    });
  });

  describe("Function 'configureLookBackPeriod()'", async () => {
    it("Executes as expected", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const expectedLookBackPeriodRecord: LookBackPeriodRecord = {
        effectiveDay: YIELD_STREAMER_INIT_DAY,
        length: BigNumber.from(LOOK_BACK_PERIOD_LENGTH)
      };

      await expect(
        context.yieldStreamer.configureLookBackPeriod(
          expectedLookBackPeriodRecord.effectiveDay,
          expectedLookBackPeriodRecord.length
        )
      ).to.emit(
        context.yieldStreamer,
        EVENT_LOOK_BACK_PERIOD_CONFIGURED
      ).withArgs(expectedLookBackPeriodRecord.effectiveDay, expectedLookBackPeriodRecord.length);

      await checkLookBackPeriods(context.yieldStreamer, [expectedLookBackPeriodRecord]);
    });

    it("Is reverted if it is called not by the owner", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const effectiveDay = YIELD_STREAMER_INIT_DAY + 1;

      await expect(
        context.yieldStreamer.connect(user).configureLookBackPeriod(effectiveDay, LOOK_BACK_PERIOD_LENGTH)
      ).revertedWith(REVERT_MESSAGE_OWNABLE_CALLER_IS_NOT_THE_OWNER);
    });

    it("Is reverted if the effective day is invalid", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const effectiveDay = YIELD_STREAMER_INIT_DAY + 1;

      await proveTx(context.yieldStreamer.configureLookBackPeriod(effectiveDay, LOOK_BACK_PERIOD_LENGTH));

      await expect(
        context.yieldStreamer.configureLookBackPeriod(effectiveDay, LOOK_BACK_PERIOD_LENGTH)
      ).revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_LOOK_BACK_PERIOD_INVALID_EFFECTIVE_DAY);
    });

    it("Is reverted if the same length is already configured", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const effectiveDay = YIELD_STREAMER_INIT_DAY + 1;

      await proveTx(context.yieldStreamer.configureLookBackPeriod(effectiveDay, LOOK_BACK_PERIOD_LENGTH));

      await expect(
        context.yieldStreamer.configureLookBackPeriod(effectiveDay + 1, LOOK_BACK_PERIOD_LENGTH)
      ).revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_LOOK_BACK_PERIOD_LENGTH_ALREADY_CONFIGURED);
    });

    it("Is reverted if the new length is zero", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const effectiveDay = YIELD_STREAMER_INIT_DAY + 1;

      await expect(
        context.yieldStreamer.configureLookBackPeriod(effectiveDay, BIG_NUMBER_ZERO)
      ).revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_LOOK_BACK_PERIOD_LENGTH_ZERO);
    });

    it("Is reverted if the parameters combination is wrong", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const effectiveDay = LOOK_BACK_PERIOD_LENGTH - 2;

      await expect(
        context.yieldStreamer.configureLookBackPeriod(effectiveDay, LOOK_BACK_PERIOD_LENGTH)
      ).revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_LOOK_BACK_PERIOD_INVALID_PARAMETERS_COMBINATION);
    });

    it("Is reverted if a look-back period is already configured", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const effectiveDay = YIELD_STREAMER_INIT_DAY + 1;

      await proveTx(context.yieldStreamer.configureLookBackPeriod(effectiveDay, LOOK_BACK_PERIOD_LENGTH));

      await expect(
        context.yieldStreamer.configureLookBackPeriod(effectiveDay + 1, LOOK_BACK_PERIOD_LENGTH + 1)
      ).revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_LOOK_BACK_PERIOD_COUNT_LIMIT);
    });
  });

  describe("Function 'updateLookBackPeriod()'", async () => {
    it("Executes as expected", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const expectedLookBackPeriodRecord: LookBackPeriodRecord = {
        effectiveDay: YIELD_STREAMER_INIT_DAY,
        length: BigNumber.from(LOOK_BACK_PERIOD_LENGTH)
      };

      await proveTx(
        context.yieldStreamer.configureLookBackPeriod(
          expectedLookBackPeriodRecord.effectiveDay,
          expectedLookBackPeriodRecord.length
        )
      );

      await checkLookBackPeriods(context.yieldStreamer, [expectedLookBackPeriodRecord]);

      expectedLookBackPeriodRecord.effectiveDay = YIELD_STREAMER_INIT_DAY + 1;
      expectedLookBackPeriodRecord.length = BigNumber.from(LOOK_BACK_PERIOD_LENGTH + 1);

      await expect(
        context.yieldStreamer.updateLookBackPeriod(
          expectedLookBackPeriodRecord.effectiveDay,
          expectedLookBackPeriodRecord.length,
          LOOK_BACK_PERIOD_INDEX_ZERO
        )
      ).to.emit(
        context.yieldStreamer,
        EVENT_LOOK_BACK_PERIOD_UPDATED
      ).withArgs(
        LOOK_BACK_PERIOD_INDEX_ZERO,
        YIELD_STREAMER_INIT_DAY + 1,
        YIELD_STREAMER_INIT_DAY,
        LOOK_BACK_PERIOD_LENGTH + 1,
        LOOK_BACK_PERIOD_LENGTH
      );

      await checkLookBackPeriods(context.yieldStreamer, [expectedLookBackPeriodRecord]);
    });

    it("Is reverted if it is called not by the owner", async () => {
      const context: TestContext = await setUpFixture(deployContracts);

      await proveTx(context.yieldStreamer.configureLookBackPeriod(YIELD_STREAMER_INIT_DAY, LOOK_BACK_PERIOD_LENGTH));

      await expect(
        context.yieldStreamer
          .connect(user)
          .updateLookBackPeriod(YIELD_STREAMER_INIT_DAY + 1, LOOK_BACK_PERIOD_LENGTH + 1, LOOK_BACK_PERIOD_INDEX_ZERO)
      ).revertedWith(REVERT_MESSAGE_OWNABLE_CALLER_IS_NOT_THE_OWNER);
    });

    it("Is reverted if look backs are not configured", async () => {
      const context: TestContext = await setUpFixture(deployContracts);

      await expect(
        context.yieldStreamer.updateLookBackPeriod(
          YIELD_STREAMER_INIT_DAY,
          LOOK_BACK_PERIOD_LENGTH,
          LOOK_BACK_PERIOD_INDEX_ZERO
        )
      ).revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_LOOK_BACK_PERIOD_WRONG_INDEX);
    });

    it("Is reverted if the new length is zero", async () => {
      const context: TestContext = await setUpFixture(deployContracts);

      await proveTx(context.yieldStreamer.configureLookBackPeriod(YIELD_STREAMER_INIT_DAY, LOOK_BACK_PERIOD_LENGTH));

      await expect(
        context.yieldStreamer.updateLookBackPeriod(
          YIELD_STREAMER_INIT_DAY + 1,
          BIG_NUMBER_ZERO,
          LOOK_BACK_PERIOD_INDEX_ZERO
        )
      ).revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_LOOK_BACK_PERIOD_LENGTH_ZERO);
    });

    it("Is reverted if the parameters combination is wrong", async () => {
      const context: TestContext = await setUpFixture(deployContracts);

      await proveTx(context.yieldStreamer.configureLookBackPeriod(YIELD_STREAMER_INIT_DAY, LOOK_BACK_PERIOD_LENGTH));

      await expect(
        context.yieldStreamer.updateLookBackPeriod(
          LOOK_BACK_PERIOD_LENGTH - 2,
          LOOK_BACK_PERIOD_LENGTH,
          LOOK_BACK_PERIOD_INDEX_ZERO
        )
      ).revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_LOOK_BACK_PERIOD_INVALID_PARAMETERS_COMBINATION);
    });

    it("Is reverted if the look-back period index is wrong", async () => {
      const context: TestContext = await setUpFixture(deployContracts);

      await proveTx(context.yieldStreamer.configureLookBackPeriod(YIELD_STREAMER_INIT_DAY, LOOK_BACK_PERIOD_LENGTH));

      await expect(
        context.yieldStreamer.updateLookBackPeriod(
          YIELD_STREAMER_INIT_DAY + 1,
          LOOK_BACK_PERIOD_LENGTH + 1,
          LOOK_BACK_PERIOD_INDEX_ZERO + 1
        )
      ).revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_LOOK_BACK_PERIOD_WRONG_INDEX);
    });
  });

  describe("Function 'configureYieldRate()'", async () => {
    it("Executes as expected", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const [expectedYieldRateRecord1, expectedYieldRateRecord2] = defineExpectedYieldRateRecords();

      await expect(
        context.yieldStreamer.configureYieldRate(
          GROUP_ONE_ID,
          expectedYieldRateRecord1.effectiveDay,
          expectedYieldRateRecord1.value
        )
      ).to.emit(
        context.yieldStreamer,
        EVENT_YIELD_RATE_CONFIGURED
      ).withArgs(
        GROUP_ONE_ID,
        expectedYieldRateRecord1.effectiveDay,
        expectedYieldRateRecord1.value
      );

      await expect(
        context.yieldStreamer.configureYieldRate(
          GROUP_ONE_ID,
          expectedYieldRateRecord2.effectiveDay,
          expectedYieldRateRecord2.value
        )
      ).to.emit(
        context.yieldStreamer,
        EVENT_YIELD_RATE_CONFIGURED
      ).withArgs(
        GROUP_ONE_ID,
        expectedYieldRateRecord2.effectiveDay,
        expectedYieldRateRecord2.value
      );

      await checkYieldRates(context.yieldStreamer, [expectedYieldRateRecord1, expectedYieldRateRecord2], GROUP_ONE_ID);
      await checkYieldRates(context.yieldStreamer, [], ZERO_GROUP_ID);
    });

    it("Is reverted if it is called not by the owner", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const effectiveDay = YIELD_STREAMER_INIT_DAY + 1;

      await expect(
        context.yieldStreamer.connect(user).configureYieldRate(ZERO_GROUP_ID, effectiveDay, INITIAL_YIELD_RATE)
      ).revertedWith(REVERT_MESSAGE_OWNABLE_CALLER_IS_NOT_THE_OWNER);
    });

    it("Is reverted if the effective day is invalid", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const effectiveDay = YIELD_STREAMER_INIT_DAY + 1;

      await proveTx(context.yieldStreamer.configureYieldRate(ZERO_GROUP_ID, effectiveDay, INITIAL_YIELD_RATE));

      await expect(
        context.yieldStreamer.configureYieldRate(ZERO_GROUP_ID, effectiveDay, INITIAL_YIELD_RATE)
      ).revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_YIELD_RATE_INVALID_EFFECTIVE_DAY);
    });

    it("Is reverted if the same value is already configured", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const effectiveDay = YIELD_STREAMER_INIT_DAY + 1;

      await proveTx(context.yieldStreamer.configureYieldRate(ZERO_GROUP_ID, effectiveDay, INITIAL_YIELD_RATE));

      await expect(
        context.yieldStreamer.configureYieldRate(ZERO_GROUP_ID, effectiveDay + 1, INITIAL_YIELD_RATE)
      ).revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_YIELD_RATE_VALUE_ALREADY_CONFIGURED);
    });

    // This test is to cover the internal function `_toUint16()`
    it("Is reverted if the effective day index is greater than 16-bit unsigned integer", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const effectiveDay = 65536;

      await expect(
        context.yieldStreamer.configureYieldRate(ZERO_GROUP_ID, effectiveDay, INITIAL_YIELD_RATE)
      ).revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_SAFE_CAST_OVERFLOW_UINT16);
    });

    // This test is to cover the internal function `_toUint240()`
    it("Is reverted if the new value is greater than 240-bit unsigned integer", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const effectiveDay = YIELD_STREAMER_INIT_DAY + 1;
      const yieldRateValue: BigNumber = BigNumber.from(
        "0x1000000000000000000000000000000000000000000000000000000000000"
      );

      await expect(
        context.yieldStreamer.configureYieldRate(ZERO_GROUP_ID, effectiveDay, yieldRateValue)
      ).revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_SAFE_CAST_OVERFLOW_UINT240);
    });
  });

  describe("Function 'stopStreamingFor()'", async () => {
    it("Executes as expected and emits the corresponding events", async () => {
      const { yieldStreamer } = await setUpFixture(deployContracts);
      await proveTx(yieldStreamer.setMainBlocklister(blocklister.address));
      const userAddresses = [user.address, user2.address];

      const tx = yieldStreamer.connect(blocklister).stopStreamingFor(userAddresses);
      const expectedStopTimestamp = await getTxTimestamp(tx) + TIME_SHIFT_IN_SECONDS;

      // Verify the event was emitted and the stop timestamp was stored for each user
      for (const userAddress of userAddresses) {
        await expect(tx).to.emit(yieldStreamer, EVENT_YIELD_STREAMING_STOPPED).withArgs(userAddress);
        const actualStopTime = await yieldStreamer.getYieldStreamingStopTimestamp(userAddress);
        expect(actualStopTime).to.equal(expectedStopTimestamp);
      }
    });

    it("Is reverted if caller is not a blocklister", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      await expect(context.yieldStreamer.connect(user).stopStreamingFor([user.address]))
        .to.be.revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_CALLER_NOT_BLOCKLISTER)
        .withArgs(user.address);
    });

    it("Is reverted when trying to stop streaming for an account that already has streaming stopped", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      await proveTx(context.yieldStreamer.setMainBlocklister(blocklister.address));

      // First call should succeed
      await proveTx(context.yieldStreamer.connect(blocklister).stopStreamingFor([user.address]));

      // Second call should revert with StreamingAlreadyStopped
      await expect(
        context.yieldStreamer.connect(blocklister).stopStreamingFor([user2.address, user.address])
      ).to.be.revertedWithCustomError(context.yieldStreamer, "StreamingAlreadyStopped")
        .withArgs(user.address);
    });
  });

  describe("Function 'updateYieldRate()'", async () => {
    it("Executes as expected if there are three yield rate records configured", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const oldExpectedYieldRateRecords = defineExpectedYieldRateRecords();
      const newExpectedYieldRateRecord = [...oldExpectedYieldRateRecords];
      const recordIndex = Math.floor(oldExpectedYieldRateRecords.length / 2);
      newExpectedYieldRateRecord[recordIndex] = {
        effectiveDay: oldExpectedYieldRateRecords[recordIndex].effectiveDay + 1,
        value: BigNumber.from(oldExpectedYieldRateRecords[recordIndex].value.add(1))
      };

      for (const expectedYieldRateRecord of oldExpectedYieldRateRecords) {
        await proveTx(
          context.yieldStreamer.configureYieldRate(
            ZERO_GROUP_ID,
            expectedYieldRateRecord.effectiveDay,
            expectedYieldRateRecord.value
          )
        );
      }

      await expect(
        context.yieldStreamer.updateYieldRate(
          ZERO_GROUP_ID,
          newExpectedYieldRateRecord[recordIndex].effectiveDay,
          newExpectedYieldRateRecord[recordIndex].value,
          recordIndex
        )
      ).to.emit(
        context.yieldStreamer,
        EVENT_YIELD_RATE_UPDATED
      ).withArgs(
        ZERO_GROUP_ID,
        recordIndex,
        newExpectedYieldRateRecord[recordIndex].effectiveDay,
        oldExpectedYieldRateRecords[recordIndex].effectiveDay,
        newExpectedYieldRateRecord[recordIndex].value,
        oldExpectedYieldRateRecords[recordIndex].value
      );

      await checkYieldRates(context.yieldStreamer, newExpectedYieldRateRecord, ZERO_GROUP_ID);
    });

    it("Executes as expected if there is only one yield rate record configured", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const [oldExpectedYieldRateRecord] = defineExpectedYieldRateRecords();
      const newExpectedYieldRateRecord: YieldRateRecord = {
        effectiveDay: oldExpectedYieldRateRecord.effectiveDay + 1,
        value: BigNumber.from(oldExpectedYieldRateRecord.value.add(1))
      };

      await proveTx(
        context.yieldStreamer.configureYieldRate(
          ZERO_GROUP_ID,
          oldExpectedYieldRateRecord.effectiveDay,
          oldExpectedYieldRateRecord.value
        )
      );

      await expect(
        context.yieldStreamer.updateYieldRate(
          ZERO_GROUP_ID,
          newExpectedYieldRateRecord.effectiveDay,
          newExpectedYieldRateRecord.value,
          YIELD_RATE_INDEX_ZERO
        )
      ).to.emit(
        context.yieldStreamer,
        EVENT_YIELD_RATE_UPDATED
      ).withArgs(
        ZERO_GROUP_ID,
        YIELD_RATE_INDEX_ZERO,
        newExpectedYieldRateRecord.effectiveDay,
        oldExpectedYieldRateRecord.effectiveDay,
        newExpectedYieldRateRecord.value,
        oldExpectedYieldRateRecord.value
      );

      await checkYieldRates(context.yieldStreamer, [newExpectedYieldRateRecord], ZERO_GROUP_ID);
    });

    it("Is reverted if it is called not by the owner", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const effectiveDay = YIELD_STREAMER_INIT_DAY + 1;

      await expect(
        context.yieldStreamer.connect(user).updateYieldRate(
          ZERO_GROUP_ID,
          effectiveDay,
          INITIAL_YIELD_RATE,
          YIELD_RATE_INDEX_ZERO
        )
      ).revertedWith(REVERT_MESSAGE_OWNABLE_CALLER_IS_NOT_THE_OWNER);
    });

    it("Is reverted if yield rates are not configured", async () => {
      const context: TestContext = await setUpFixture(deployContracts);

      await expect(
        context.yieldStreamer.updateYieldRate(
          ZERO_GROUP_ID,
          YIELD_STREAMER_INIT_DAY,
          INITIAL_YIELD_RATE,
          YIELD_RATE_INDEX_ZERO
        )
      ).revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_YIELD_RATE_WRONG_INDEX);
    });

    it("Is reverted if the index is out of yield rate array", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const effectiveDay = YIELD_STREAMER_INIT_DAY + 1;

      await proveTx(context.yieldStreamer.configureYieldRate(ZERO_GROUP_ID, effectiveDay, INITIAL_YIELD_RATE));

      await expect(
        context.yieldStreamer.updateYieldRate(
          ZERO_GROUP_ID,
          effectiveDay,
          INITIAL_YIELD_RATE,
          YIELD_RATE_INDEX_ZERO + 1
        )
      ).revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_YIELD_RATE_WRONG_INDEX);
    });

    it("Is reverted if the effective day is invalid", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const expectedYieldRateRecords: YieldRateRecord[] = defineExpectedYieldRateRecords();

      for (const expectedYieldRateRecord of expectedYieldRateRecords) {
        await proveTx(
          context.yieldStreamer.configureYieldRate(
            ZERO_GROUP_ID,
            expectedYieldRateRecord.effectiveDay,
            expectedYieldRateRecord.value
          )
        );
      }

      let recordIndex = 0;
      // check revert if effective day is greater than next day if there is updating day with index 0
      await expect(
        context.yieldStreamer.updateYieldRate(
          ZERO_GROUP_ID,
          expectedYieldRateRecords[recordIndex + 1].effectiveDay,
          expectedYieldRateRecords[recordIndex].value,
          recordIndex
        )
      ).revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_YIELD_RATE_INVALID_EFFECTIVE_DAY);

      recordIndex = 1;
      // Check revert if effective day is less than previous day
      await expect(
        context.yieldStreamer.updateYieldRate(
          ZERO_GROUP_ID,
          expectedYieldRateRecords[recordIndex - 1].effectiveDay,
          expectedYieldRateRecords[recordIndex].value,
          recordIndex
        )
      ).revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_YIELD_RATE_INVALID_EFFECTIVE_DAY);

      // check revert if effective day is greater than next day with index != 0
      await expect(
        context.yieldStreamer.updateYieldRate(
          ZERO_GROUP_ID,
          expectedYieldRateRecords[recordIndex + 1].effectiveDay,
          expectedYieldRateRecords[recordIndex].value,
          recordIndex
        )
      ).revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_YIELD_RATE_INVALID_EFFECTIVE_DAY);

      recordIndex = 2;
      // check revert if effective day is less than next day if the next day is last element in array
      await expect(
        context.yieldStreamer.updateYieldRate(
          ZERO_GROUP_ID,
          expectedYieldRateRecords[recordIndex - 1].effectiveDay,
          expectedYieldRateRecords[recordIndex].value,
          recordIndex
        )
      ).revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_YIELD_RATE_INVALID_EFFECTIVE_DAY);
    });
  });

  describe("Function 'calculateYieldByDays()'", async () => {
    const balanceRecords: BalanceRecord[] = balanceRecordsCase1;
    const lookBackPeriodLength = LOOK_BACK_PERIOD_LENGTH;
    const dayFrom = YIELD_STREAMER_INIT_DAY + 2;
    const dayTo = balanceRecords[balanceRecords.length - 1].day + 1;
    const yieldByDaysBaseRequest: YieldByDaysRequest = {
      lookBackPeriodLength,
      yieldRateRecords: [yieldRateRecordCase1],
      balanceRecords,
      dayFrom,
      dayTo,
      claimDebit: BIG_NUMBER_ZERO
    };

    async function checkYieldByDays(context: TestContext, yieldByDaysRequest: YieldByDaysRequest) {
      await proveTx(context.balanceTrackerMock.setBalanceRecords(user.address, balanceRecords));
      for (let i = 1; i < yieldByDaysRequest.yieldRateRecords.length; ++i) {
        const yieldRateRecord: YieldRateRecord = yieldByDaysRequest.yieldRateRecords[i];
        await proveTx(
          context.yieldStreamer.configureYieldRate(ZERO_GROUP_ID, yieldRateRecord.effectiveDay, yieldRateRecord.value)
        );
      }

      const expectedYieldByDays: BigNumber[] = defineExpectedYieldByDays(yieldByDaysRequest);
      const actualYieldByDays: BigNumber[] = await context.yieldStreamer.calculateYieldByDays(
        user.address,
        dayFrom,
        dayTo,
        yieldByDaysRequest.claimDebit
      );
      expect(actualYieldByDays).to.deep.equal(expectedYieldByDays);
    }

    describe("Executes as expected if token balances are according to case 1 and", async () => {
      describe("There is only one yield record and", async () => {
        it("The claim debit is zero", async () => {
          const context: TestContext = await setUpFixture(deployAndConfigureContracts);
          const yieldByDaysRequest: YieldByDaysRequest = { ...yieldByDaysBaseRequest };
          await checkYieldByDays(context, yieldByDaysRequest);
        });

        it("The claim debit is non-zero and small", async () => {
          const context: TestContext = await setUpFixture(deployAndConfigureContracts);
          const yieldByDaysRequest: YieldByDaysRequest = { ...yieldByDaysBaseRequest };
          yieldByDaysRequest.claimDebit = BigNumber.from(123456);
          await checkYieldByDays(context, yieldByDaysRequest);
        });

        it("The claim debit is non-zero and huge", async () => {
          const context: TestContext = await setUpFixture(deployAndConfigureContracts);
          const yieldByDaysRequest: YieldByDaysRequest = { ...yieldByDaysBaseRequest };
          yieldByDaysRequest.claimDebit = BIG_NUMBER_MAX_UINT256;
          await checkYieldByDays(context, yieldByDaysRequest);
        });
      });

      describe("There are three yield records and", async () => {
        it("The claim debit is zero", async () => {
          const context: TestContext = await setUpFixture(deployAndConfigureContracts);
          const yieldByDaysRequest: YieldByDaysRequest = { ...yieldByDaysBaseRequest };
          yieldByDaysRequest.yieldRateRecords.push(yieldRateRecordCase2);
          yieldByDaysRequest.yieldRateRecords.push(yieldRateRecordCase3);
          await checkYieldByDays(context, yieldByDaysRequest);
        });
      });
    });

    describe("Is reverted if", async () => {
      it("The 'to' day is prior the 'from' day", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        const yieldByDaysRequest: YieldByDaysRequest = { ...yieldByDaysBaseRequest };
        await expect(
          context.yieldStreamer.calculateYieldByDays(user.address, dayFrom, dayFrom - 1, yieldByDaysRequest.claimDebit)
        ).to.revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_TO_DAY_PRIOR_FROM_DAY);
      });
    });
  });

  describe("Function 'getAccountYieldRates()'", async () => {
    it("Executes as expected", async () => {
      const context: TestContext = await setUpFixture(deployContracts);
      const [
        expectedYieldRateRecord1,
        expectedYieldRateRecord2
      ] = defineExpectedYieldRateRecords();
      await proveTx(context.yieldStreamer.setMainBlocklister(blocklister.address));
      await proveTx(context.yieldStreamer.configureYieldRate(
        ZERO_GROUP_ID,
        expectedYieldRateRecord1.effectiveDay,
        expectedYieldRateRecord1.value
      ));
      await proveTx(context.yieldStreamer.configureYieldRate(
        GROUP_ONE_ID,
        expectedYieldRateRecord2.effectiveDay,
        expectedYieldRateRecord2.value
      ));
      expect(expectedYieldRateRecord1.effectiveDay).not.to.equal(expectedYieldRateRecord2.effectiveDay);
      expect(expectedYieldRateRecord1.value).not.to.equal(expectedYieldRateRecord2.value);

      let userYieldRates = await context.yieldStreamer.getAccountYieldRates(user.address);
      let actualUserYieldRateRecord = userYieldRates[0];
      expect(actualUserYieldRateRecord[0]).to.eq(expectedYieldRateRecord1.effectiveDay);
      expect(actualUserYieldRateRecord[1]).to.eq(expectedYieldRateRecord1.value);

      await proveTx(context.yieldStreamer.connect(blocklister).assignAccountGroup(GROUP_ONE_ID, [user.address]));

      userYieldRates = await context.yieldStreamer.getAccountYieldRates(user.address);
      actualUserYieldRateRecord = userYieldRates[0];
      expect(actualUserYieldRateRecord[0]).to.eq(expectedYieldRateRecord2.effectiveDay);
      expect(actualUserYieldRateRecord[1]).to.eq(expectedYieldRateRecord2.value);
    });
  });

  describe("Function 'claimAllPreview()'", async () => {
    describe("Executes as expected if", async () => {
      const baseClaimRequest: ClaimRequest = {
        amount: BIG_NUMBER_MAX_UINT256,
        firstYieldDay: YIELD_STREAMER_INIT_DAY,
        claimDay: YIELD_STREAMER_INIT_DAY + 10,
        claimTime: 12 * 3600,
        claimDebit: BIG_NUMBER_ZERO,
        lookBackPeriodLength: LOOK_BACK_PERIOD_LENGTH,
        yieldRateRecords: [yieldRateRecordCase1],
        balanceRecords: balanceRecordsCase1
      };

      async function executeAndCheckClaimAll(
        context: TestContext,
        claimRequest: ClaimRequest
      ): Promise<ClaimResult> {
        await proveTx(context.balanceTrackerMock.setBalanceRecords(user.address, claimRequest.balanceRecords));
        const actualClaimResult = await context.yieldStreamer.claimAllPreview(user.address);
        const expectedClaimResult = defineExpectedClaimResult(claimRequest);
        compareClaimPreviews(actualClaimResult, expectedClaimResult);
        return actualClaimResult;
      }

      it("Token balances are according to case 1", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        await proveTx(context.balanceTrackerMock.setDayAndTime(baseClaimRequest.claimDay, baseClaimRequest.claimTime));
        await executeAndCheckClaimAll(context, baseClaimRequest);
      });

      it("Token min daily balance becomes larger than yield-generating daily balance limit", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        const claimRequest: ClaimRequest = { ...baseClaimRequest };
        claimRequest.claimDay = YIELD_STREAMER_INIT_DAY + 3;
        claimRequest.balanceRecords = [
          { day: BALANCE_TRACKER_INIT_DAY, value: BigNumber.from(500_000_000_000) },
          { day: BALANCE_TRACKER_INIT_DAY + 1, value: BigNumber.from(150_000_000_000) },
          { day: BALANCE_TRACKER_INIT_DAY + 2, value: BigNumber.from(300_000_000_000) }
        ];
        expect(claimRequest.balanceRecords[0].value).to.be.greaterThan(MAX_DAILY_BALANCE_LIMIT);
        expect(claimRequest.balanceRecords[1].value).to.be.lessThan(MAX_DAILY_BALANCE_LIMIT);
        expect(claimRequest.balanceRecords[2].value).to.be.greaterThan(MAX_DAILY_BALANCE_LIMIT);

        await proveTx(context.balanceTrackerMock.setDayAndTime(claimRequest.claimDay, claimRequest.claimTime));
        const actualClaimResult1 = await executeAndCheckClaimAll(context, claimRequest);

        claimRequest.balanceRecords[1].value = claimRequest.balanceRecords[1].value.add(BigNumber.from(50_000_000_000));
        expect(claimRequest.balanceRecords[1].value).to.be.equal(MAX_DAILY_BALANCE_LIMIT);
        const actualClaimResult2 = await executeAndCheckClaimAll(context, claimRequest);

        claimRequest.balanceRecords[1].value = claimRequest.balanceRecords[1].value.add(BigNumber.from(50_000_000_000));
        expect(claimRequest.balanceRecords[1].value).to.be.greaterThan(MAX_DAILY_BALANCE_LIMIT);
        const actualClaimResult3 = await executeAndCheckClaimAll(context, claimRequest);

        expect(actualClaimResult1.yield).to.be.lessThan(actualClaimResult2.yield);
        compareClaimPreviews(actualClaimResult2, actualClaimResult3);
      });

      it("The streaming is stopped for the account but stopped timestamp is after the current one", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        const { yieldStreamer, balanceTrackerMock } = context;
        const claimRequest: ClaimRequest = { ...baseClaimRequest };
        await proveTx(balanceTrackerMock.setDayAndTime(claimRequest.claimDay, claimRequest.claimTime));
        const timestamp = (baseClaimRequest.claimDay + 1) * 24 * 3600 + baseClaimRequest.claimTime;
        await proveTx(yieldStreamer.setStreamingStopTimestamp(user.address, timestamp)); // Call via the testable ver.
        await executeAndCheckClaimAll(context, claimRequest);
      });

      it("The streaming is stopped for the account and stopped timestamp equals the current one", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        const { yieldStreamer, balanceTrackerMock } = context;
        const claimRequest: ClaimRequest = { ...baseClaimRequest };
        await proveTx(balanceTrackerMock.setDayAndTime(claimRequest.claimDay, claimRequest.claimTime));
        const timestamp = baseClaimRequest.claimDay * 24 * 3600 + baseClaimRequest.claimTime;
        await proveTx(yieldStreamer.setStreamingStopTimestamp(user.address, timestamp)); // Call via the testable ver.
        await executeAndCheckClaimAll(context, claimRequest);
      });

      it("The streaming is stopped for the account and stopped timestamp is before the current one", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        const { yieldStreamer, balanceTrackerMock } = context;
        const claimRequest: ClaimRequest = { ...baseClaimRequest };
        await proveTx(balanceTrackerMock.setDayAndTime(claimRequest.claimDay, claimRequest.claimTime));

        // Streaming stop timestamp is 1 day before the claim timestamp
        const timestamp1 = (baseClaimRequest.claimDay - 1) * 24 * 3600 + baseClaimRequest.claimTime;
        await proveTx(yieldStreamer.setStreamingStopTimestamp(user.address, timestamp1)); // Call via the testable ver.
        {
          const expectedClaimResult1 = defineExpectedClaimResult(claimRequest);
          claimRequest.claimDay -= 1;
          const expectedClaimResult2 = defineExpectedClaimResult(claimRequest);
          expect(expectedClaimResult2.yield).to.be.lessThan(expectedClaimResult1.yield);
        }
        await executeAndCheckClaimAll(context, claimRequest);

        // Streaming stop timestamp is 1 hour before the claim timestamp
        claimRequest.claimDay = baseClaimRequest.claimDay;
        const timestamp2 = baseClaimRequest.claimDay * 24 * 3600 + baseClaimRequest.claimTime - 3600;
        await proveTx(yieldStreamer.setStreamingStopTimestamp(user.address, timestamp2)); // Call via the testable ver.
        {
          const expectedClaimResult1 = defineExpectedClaimResult(claimRequest);
          claimRequest.claimTime -= 3600;
          const expectedClaimResult2 = defineExpectedClaimResult(claimRequest);
          expect(expectedClaimResult2.yield).to.be.lessThan(expectedClaimResult1.yield);
        }
        await executeAndCheckClaimAll(context, claimRequest);
      });

      it("Returns zeroed values when the contract is archived", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);

        await proveTx(context.balanceTrackerMock.setBalanceRecords(user.address, baseClaimRequest.balanceRecords));
        await proveTx(context.balanceTrackerMock.setDayAndTime(baseClaimRequest.claimDay, baseClaimRequest.claimTime));

        const preArchiveResult = await context.yieldStreamer.claimAllPreview(user.address);
        expect(preArchiveResult.yield).to.not.equal(BIG_NUMBER_ZERO);

        await proveTx(context.yieldStreamer.setIsArchived(true));

        const postArchiveResult = await context.yieldStreamer.claimAllPreview(user.address);
        compareClaimPreviews(postArchiveResult, EMPTY_CLAIM_RESULT);
      });
    });
  });

  describe("Function 'claimPreview()'", async () => {
    describe("Executes as expected if token balances are according to case 1 and", async () => {
      const baseClaimRequest: ClaimRequest = {
        amount: BIG_NUMBER_MAX_UINT256,
        firstYieldDay: YIELD_STREAMER_INIT_DAY,
        claimDay: YIELD_STREAMER_INIT_DAY + 10,
        claimTime: 12 * 3600,
        claimDebit: BIG_NUMBER_ZERO,
        lookBackPeriodLength: LOOK_BACK_PERIOD_LENGTH,
        yieldRateRecords: [yieldRateRecordCase1],
        balanceRecords: balanceRecordsCase1
      };

      async function checkClaimPreview(context: TestContext, claimRequest: ClaimRequest) {
        await proveTx(context.balanceTrackerMock.setBalanceRecords(user.address, claimRequest.balanceRecords));
        await proveTx(context.balanceTrackerMock.setDayAndTime(claimRequest.claimDay, claimRequest.claimTime));
        const expectedClaimResult: ClaimResult = defineExpectedClaimResult(claimRequest);
        const actualClaimResult = await context.yieldStreamer.claimPreview(user.address, claimRequest.amount);
        compareClaimPreviews(actualClaimResult, expectedClaimResult);
      }

      it("The amount equals a half of the possible primary yield", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        const claimRequest: ClaimRequest = { ...baseClaimRequest };
        const expectedClaimAllResult: ClaimResult = defineExpectedClaimResult(claimRequest);

        claimRequest.amount = roundDown(expectedClaimAllResult.primaryYield.div(2));
        await checkClaimPreview(context, claimRequest);
      });

      it("The amount equals the possible primary yield plus a third of the possible stream yield", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        const claimRequest: ClaimRequest = { ...baseClaimRequest };
        const expectedClaimAllResult: ClaimResult = defineExpectedClaimResult(claimRequest);

        claimRequest.amount = roundDown(
          expectedClaimAllResult.primaryYield.add(expectedClaimAllResult.streamYield.div(3))
        );
        await checkClaimPreview(context, claimRequest);
      });

      it("The amount is greater than possible primary yield plus the possible stream yield", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        const claimRequest: ClaimRequest = { ...baseClaimRequest };
        const expectedClaimAllResult: ClaimResult = defineExpectedClaimResult(claimRequest);
        const expectedShortfall = roundUpward(BigNumber.from(1));

        claimRequest.amount = expectedClaimAllResult.yield.add(expectedShortfall);
        await checkClaimPreview(context, claimRequest);
      });

      it("The amount equals the minimum allowed claim amount", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        const claimRequest: ClaimRequest = { ...baseClaimRequest };

        claimRequest.amount = MIN_CLAIM_AMOUNT;
        await checkClaimPreview(context, claimRequest);
      });

      it("Returns zeroed values when the contract is archived", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        const claimRequest = { ...baseClaimRequest, amount: MIN_CLAIM_AMOUNT };

        await proveTx(context.balanceTrackerMock.setBalanceRecords(user.address, claimRequest.balanceRecords));
        await proveTx(context.balanceTrackerMock.setDayAndTime(claimRequest.claimDay, claimRequest.claimTime));
        const preArchiveResult = await context.yieldStreamer.claimPreview(user.address, claimRequest.amount);
        expect(preArchiveResult.yield).to.not.equal(BIG_NUMBER_ZERO);

        await proveTx(context.yieldStreamer.setIsArchived(true));

        const postArchiveResult = await context.yieldStreamer.claimPreview(user.address, claimRequest.amount);
        compareClaimPreviews(postArchiveResult, EMPTY_CLAIM_RESULT);
      });

      // Cases with balance limit and stream stopping for an account are not tested here
      // because they are already covered in the 'claimAllPreview()' tests.
      // Both functions use the same internal logic, so we avoid duplicating these test cases.
    });
    describe("Is reverted if", async () => {
      it("The amount is below the allowed minimum", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        await expect(
          context.yieldStreamer.claimPreview(user.address, MIN_CLAIM_AMOUNT.sub(1))
        ).to.be.revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_CLAIM_AMOUNT_BELOW_MINIMUM);
      });

      it("The amount is non-rounded", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        await expect(
          context.yieldStreamer.claimPreview(user.address, MIN_CLAIM_AMOUNT.add(1))
        ).to.be.revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_CLAIM_AMOUNT_NON_ROUNDED);
      });
    });
  });

  describe("Function 'claim()'", async () => {
    const baseClaimRequest: ClaimRequest = {
      amount: BIG_NUMBER_MAX_UINT256,
      firstYieldDay: YIELD_STREAMER_INIT_DAY,
      claimDay: YIELD_STREAMER_INIT_DAY + 10,
      claimTime: 12 * 3600,
      claimDebit: BIG_NUMBER_ZERO,
      lookBackPeriodLength: LOOK_BACK_PERIOD_LENGTH,
      yieldRateRecords: [yieldRateRecordCase1],
      balanceRecords: balanceRecordsCase1
    };

    async function checkClaim(context: TestContext, claimRequest: ClaimRequest) {
      await proveTx(context.balanceTrackerMock.setBalanceRecords(user.address, claimRequest.balanceRecords));
      await proveTx(context.balanceTrackerMock.setDayAndTime(claimRequest.claimDay, claimRequest.claimTime));
      const expectedClaimResult: ClaimResult = defineExpectedClaimResult(claimRequest);
      const totalYield: BigNumber = claimRequest.amount;
      const totalYieldWithoutFee: BigNumber = totalYield.sub(expectedClaimResult.fee);
      const tx: TransactionResponse = await context.yieldStreamer.connect(user).claim(claimRequest.amount);

      await expect(tx)
        .to.emit(context.yieldStreamer, EVENT_CLAIM)
        .withArgs(user.address, totalYield, expectedClaimResult.fee);

      await expect(tx).to.changeTokenBalances(
        context.tokenMock,
        [context.yieldStreamer, user, feeReceiver],
        [BIG_NUMBER_ZERO.sub(totalYield), totalYieldWithoutFee, expectedClaimResult.fee]
      );

      const actualClaimState = await context.yieldStreamer.getLastClaimDetails(user.address);
      expect(actualClaimState.day).to.equal(expectedClaimResult.nextClaimDay);
      expect(actualClaimState.debit).to.equal(expectedClaimResult.nextClaimDebit);
    }

    describe("Executes as expected if token balances are according to case 1 and", async () => {
      it("The amount equals a half of the possible primary yield", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        const claimRequest: ClaimRequest = { ...baseClaimRequest };
        const expectedClaimAllResult: ClaimResult = defineExpectedClaimResult(claimRequest);

        claimRequest.amount = roundDown(expectedClaimAllResult.primaryYield.div(2));
        await checkClaim(context, claimRequest);
      });

      it("The amount equals the possible primary yield plus a half of the possible stream yield", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        const claimRequest: ClaimRequest = { ...baseClaimRequest };
        const expectedClaimAllResult: ClaimResult = defineExpectedClaimResult(claimRequest);

        claimRequest.amount = roundDown(
          expectedClaimAllResult.primaryYield.add(expectedClaimAllResult.streamYield.div(2))
        );
        await checkClaim(context, claimRequest);
      });

      it("The amount equals the minimum allowed claim amount", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        const claimRequest: ClaimRequest = { ...baseClaimRequest };

        claimRequest.amount = MIN_CLAIM_AMOUNT;
        await checkClaim(context, claimRequest);
      });

      // Cases with balance limit and stream stopping for an account are not tested here
      // because they are already covered in the 'claimAllPreview()' tests.
      // Both functions use the same internal logic, so we avoid duplicating these test cases.
    });

    describe("Is reverted if", async () => {
      it("The contract is paused", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        await proveTx(context.yieldStreamer.setPauser(deployer.address));
        await proveTx(context.yieldStreamer.pause());

        await expect(context.yieldStreamer.connect(user).claim(0)).to.be.revertedWith(REVERT_MESSAGE_PAUSABLE_PAUSED);
      });

      it("The user is blocklisted", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        await proveTx(context.yieldStreamer.connect(user).selfBlocklist());

        await expect(context.yieldStreamer.connect(user).claim(0))
          .to.be.revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_BLOCKLISTED_ACCOUNT)
          .withArgs(user.address);
      });

      it("The amount is greater than possible primary yield plus the possible stream yield", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        const claimRequest: ClaimRequest = { ...baseClaimRequest };
        const expectedClaimAllResult: ClaimResult = defineExpectedClaimResult(claimRequest);
        const expectedShortfall = roundUpward(BigNumber.from(1));

        claimRequest.amount = expectedClaimAllResult.yield.add(expectedShortfall);

        await proveTx(context.balanceTrackerMock.setBalanceRecords(user.address, claimRequest.balanceRecords));
        await proveTx(context.balanceTrackerMock.setDayAndTime(claimRequest.claimDay, claimRequest.claimTime));

        await expect(
          context.yieldStreamer.connect(user).claim(claimRequest.amount)
        ).to.be.revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_CLAIM_REJECTION_DUE_TO_SHORTFALL);
      });

      it("The amount is below the allowed minimum", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        await expect(
          context.yieldStreamer.connect(user).claim(MIN_CLAIM_AMOUNT.sub(1))
        ).to.be.revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_CLAIM_AMOUNT_BELOW_MINIMUM);
      });

      it("The amount is non-rounded", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        await expect(
          context.yieldStreamer.connect(user).claim(MIN_CLAIM_AMOUNT.add(1))
        ).to.be.revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_CLAIM_AMOUNT_NON_ROUNDED);
      });
    });
  });

  describe("Complex claim scenarios", async () => {
    async function executeAndCheckPartialClaim(context: TestContext, claimRequest: ClaimRequest) {
      const expectedClaimResult: ClaimResult = defineExpectedClaimResult(claimRequest);
      const expectedClaimAllResult: ClaimResult = defineExpectedClaimAllResult(claimRequest);
      const actualClaimResult = await context.yieldStreamer.claimPreview(user.address, claimRequest.amount);
      const actualClaimAllResult = await context.yieldStreamer.claimAllPreview(user.address);
      compareClaimPreviews(actualClaimResult, expectedClaimResult);
      compareClaimPreviews(actualClaimAllResult, expectedClaimAllResult);

      const totalYield: BigNumber = claimRequest.amount;
      const totalYieldWithoutFee: BigNumber = totalYield.sub(expectedClaimResult.fee);

      const tx: TransactionResponse = await context.yieldStreamer.connect(user).claim(claimRequest.amount);

      await expect(tx)
        .to.emit(context.yieldStreamer, EVENT_CLAIM)
        .withArgs(user.address, totalYield, expectedClaimResult.fee);

      await expect(tx).to.changeTokenBalances(
        context.tokenMock,
        [context.yieldStreamer, user, feeReceiver],
        [BIG_NUMBER_ZERO.sub(totalYield), totalYieldWithoutFee, expectedClaimResult.fee]
      );

      return expectedClaimResult;
    }

    function defineYieldForFirstClaimDay(context: TestContext, claimRequest: ClaimRequest): BigNumber {
      return defineExpectedYieldByDays({
        lookBackPeriodLength: claimRequest.lookBackPeriodLength,
        yieldRateRecords: claimRequest.yieldRateRecords,
        balanceRecords: claimRequest.balanceRecords,
        dayFrom: claimRequest.firstYieldDay,
        dayTo: claimRequest.firstYieldDay,
        claimDebit: claimRequest.claimDebit
      })[0];
    }

    const balanceRecords: BalanceRecord[] = balanceRecordsCase1;

    const baseClaimRequest: ClaimRequest = {
      amount: BIG_NUMBER_MAX_UINT256,
      firstYieldDay: YIELD_STREAMER_INIT_DAY,
      claimDay: YIELD_STREAMER_INIT_DAY + 10,
      claimTime: 12 * 3600,
      claimDebit: BIG_NUMBER_ZERO,
      lookBackPeriodLength: LOOK_BACK_PERIOD_LENGTH,
      yieldRateRecords: [yieldRateRecordCase1],
      balanceRecords: balanceRecords
    };

    it("Case 1: three consecutive partial claims, never stop at the same day", async () => {
      const context: TestContext = await setUpFixture(deployAndConfigureContracts);
      await proveTx(context.balanceTrackerMock.setBalanceRecords(user.address, balanceRecords));

      const claimRequest: ClaimRequest = { ...baseClaimRequest };
      claimRequest.amount = MIN_CLAIM_AMOUNT;
      await proveTx(context.balanceTrackerMock.setDayAndTime(claimRequest.claimDay, claimRequest.claimTime));

      let claimResult: ClaimResult = await executeAndCheckPartialClaim(context, claimRequest);

      claimRequest.firstYieldDay = claimResult.nextClaimDay.toNumber();
      claimRequest.claimDebit = claimResult.nextClaimDebit;
      claimRequest.amount = roundDown(
        defineYieldForFirstClaimDay(context, claimRequest).sub(claimResult.nextClaimDebit).add(MIN_CLAIM_AMOUNT)
      );

      let previousClaimResult = claimResult;
      claimResult = await executeAndCheckPartialClaim(context, claimRequest);

      expect(previousClaimResult.firstYieldDay).to.not.equal(
        claimResult.firstYieldDay,
        "Claim 1 and claim 2 happened at the same day. Change the test conditions"
      );

      claimRequest.firstYieldDay = claimResult.nextClaimDay.toNumber();
      claimRequest.claimDebit = claimResult.nextClaimDebit;
      claimRequest.amount = roundDown(
        defineYieldForFirstClaimDay(context, claimRequest).sub(claimResult.nextClaimDebit).add(MIN_CLAIM_AMOUNT)
      );

      previousClaimResult = claimResult;
      claimResult = await executeAndCheckPartialClaim(context, claimRequest);

      expect(previousClaimResult.firstYieldDay).to.not.equal(
        claimResult.firstYieldDay,
        "Claim 2 and claim 3 happened at the same day. Change the test conditions"
      );
    });

    it("Case 2: four partial claims, two stop at some day, two stop at yesterday, then revert", async () => {
      const context: TestContext = await setUpFixture(deployAndConfigureContracts);
      await proveTx(context.balanceTrackerMock.setBalanceRecords(user.address, balanceRecords));

      const claimRequest: ClaimRequest = { ...baseClaimRequest };

      await proveTx(context.balanceTrackerMock.setDayAndTime(claimRequest.claimDay, claimRequest.claimTime));

      const expectedClaimAllResult: ClaimResult = defineExpectedClaimAllResult(claimRequest);

      claimRequest.amount = roundDown(expectedClaimAllResult.primaryYield.div(2));

      let expectedClaimResult: ClaimResult = await executeAndCheckPartialClaim(context, claimRequest);
      expect(expectedClaimResult.nextClaimDay).not.equal(
        claimRequest.claimDay - 1,
        "The next claim day after claim 1 is yesterday but it must be earlier. Change the test conditions"
      );

      claimRequest.firstYieldDay = expectedClaimResult.nextClaimDay.toNumber();
      claimRequest.claimDebit = expectedClaimResult.nextClaimDebit;
      claimRequest.amount = MIN_CLAIM_AMOUNT;

      let previousExpectedClaimResult = expectedClaimResult;
      expectedClaimResult = await executeAndCheckPartialClaim(context, claimRequest);
      expect(expectedClaimResult.nextClaimDay).to.equal(
        previousExpectedClaimResult.nextClaimDay,
        "The next yield day must be the same for claim 1 and claim 2. Change the test conditions"
      );

      claimRequest.firstYieldDay = expectedClaimResult.nextClaimDay.toNumber();
      claimRequest.claimDebit = expectedClaimResult.nextClaimDebit;
      claimRequest.amount = roundDown(expectedClaimResult.primaryYield.add(ROUNDING_COEF));

      expectedClaimResult = await executeAndCheckPartialClaim(context, claimRequest);
      expect(expectedClaimResult.nextClaimDay).equal(
        claimRequest.claimDay - 1,
        "The next claim day after claim 3 is not yesterday but it must be. Change the test conditions"
      );

      claimRequest.firstYieldDay = expectedClaimResult.nextClaimDay.toNumber();
      claimRequest.claimDebit = expectedClaimResult.nextClaimDebit;
      claimRequest.amount = MIN_CLAIM_AMOUNT;

      previousExpectedClaimResult = expectedClaimResult;
      expectedClaimResult = await executeAndCheckPartialClaim(context, claimRequest);
      expect(expectedClaimResult.nextClaimDay).to.equal(
        previousExpectedClaimResult.nextClaimDay,
        "The next yield day must be the same for claim 3 and claim 4. Change the test conditions"
      );

      claimRequest.firstYieldDay = expectedClaimResult.nextClaimDay.toNumber();
      claimRequest.claimDebit = expectedClaimResult.nextClaimDebit;
      claimRequest.amount = USER_CURRENT_TOKEN_BALANCE;

      expectedClaimResult = defineExpectedClaimResult(claimRequest);
      const actualClaimResult = await context.yieldStreamer.claimPreview(user.address, claimRequest.amount);
      compareClaimPreviews(actualClaimResult, expectedClaimResult);

      await expect(context.yieldStreamer.connect(user).claim(claimRequest.amount))
        .to.be.revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_CLAIM_REJECTION_DUE_TO_SHORTFALL)
        .withArgs(expectedClaimResult.shortfall);
    });

    it("Case 3: a partial claim that stops at yesterday, then check claim all", async () => {
      const context: TestContext = await setUpFixture(deployAndConfigureContracts);
      await proveTx(context.balanceTrackerMock.setBalanceRecords(user.address, balanceRecords));

      const claimRequest: ClaimRequest = { ...baseClaimRequest };
      claimRequest.claimTime = 23 * 3600 + 3599;

      await proveTx(context.balanceTrackerMock.setDayAndTime(claimRequest.claimDay, claimRequest.claimTime));

      let expectedClaimAllResult: ClaimResult = defineExpectedClaimAllResult(claimRequest);

      claimRequest.amount = roundDown(expectedClaimAllResult.yield.sub(MIN_CLAIM_AMOUNT.mul(1)));

      const expectedClaimResult: ClaimResult = await executeAndCheckPartialClaim(context, claimRequest);
      expect(expectedClaimResult.nextClaimDay).equal(
        claimRequest.claimDay - 1,
        "The next claim day after claim 1 is not yesterday but it must be. Change the test conditions"
      );

      claimRequest.firstYieldDay = expectedClaimResult.nextClaimDay.toNumber();
      claimRequest.claimDebit = expectedClaimResult.nextClaimDebit;
      expectedClaimAllResult = defineExpectedClaimAllResult(claimRequest);
      const actualClaimAllResult = await context.yieldStreamer.claimAllPreview(user.address);
      compareClaimPreviews(actualClaimAllResult, expectedClaimAllResult);
      expect(expectedClaimAllResult.claimDebitIsGreaterThanFirstDayYield).to.equal(
        true,
        "The claim debit is not greater that the yield, but it must be. Change the test conditions"
      );
    });

    it("Case 4: a situation when claim debit is greater than the first day yield", async () => {
      const context: TestContext = await setUpFixture(deployAndConfigureContracts);
      await proveTx(context.balanceTrackerMock.setBalanceRecords(user.address, balanceRecords));

      const claimRequest: ClaimRequest = { ...baseClaimRequest };

      await proveTx(context.balanceTrackerMock.setDayAndTime(claimRequest.claimDay, claimRequest.claimTime));

      let expectedClaimAllResult: ClaimResult = defineExpectedClaimAllResult(claimRequest);

      claimRequest.amount = roundDown(expectedClaimAllResult.primaryYield.sub(MIN_CLAIM_AMOUNT));

      const expectedClaimResult: ClaimResult = await executeAndCheckPartialClaim(context, claimRequest);
      expect(expectedClaimResult.nextClaimDay).not.equal(
        claimRequest.claimDay - 1,
        "The next claim day after the claim is yesterday but it must not be. Change the test conditions"
      );

      claimRequest.firstYieldDay = expectedClaimResult.nextClaimDay.toNumber();
      claimRequest.claimDebit = expectedClaimResult.nextClaimDebit;
      expectedClaimAllResult = defineExpectedClaimAllResult(claimRequest);
      const actualClaimAllResult = await context.yieldStreamer.claimAllPreview(user.address);
      compareClaimPreviews(actualClaimAllResult, expectedClaimAllResult);
      expect(expectedClaimAllResult.claimDebitIsGreaterThanFirstDayYield).to.equal(
        true,
        "The claim debit is not greater that the first day yield, but it must be. Change the test conditions"
      );
    });
  });

  describe("Function 'getDailyBalancesWithYield()'", async () => {
    const balanceRecords: BalanceRecord[] = balanceRecordsCase1;
    const balanceWithYieldByDaysRequestBase: BalanceWithYieldByDaysRequest = {
      lookBackPeriodLength: LOOK_BACK_PERIOD_LENGTH,
      yieldRateRecords: [yieldRateRecordCase1],
      balanceRecords: balanceRecords,
      dayFrom: YIELD_STREAMER_INIT_DAY,
      dayTo: YIELD_STREAMER_INIT_DAY,
      claimDebit: BIG_NUMBER_ZERO,
      firstYieldDay: YIELD_STREAMER_INIT_DAY
    };

    const currentDay: number = YIELD_STREAMER_INIT_DAY + 10;
    const currentTime: number = 12 * 3600;

    const claimRequestBase: ClaimRequest = {
      amount: BIG_NUMBER_MAX_UINT256,
      firstYieldDay: YIELD_STREAMER_INIT_DAY,
      claimDay: currentDay,
      claimTime: currentTime,
      claimDebit: BIG_NUMBER_ZERO,
      lookBackPeriodLength: LOOK_BACK_PERIOD_LENGTH,
      yieldRateRecords: [yieldRateRecordCase1],
      balanceRecords: balanceRecordsCase1
    };

    async function checkGetDailyBalancesWithYield(props: {
      firstDayRangeRelativeToNexClaimDay: number;
      lastDayRangeRelativeToNexClaimDay: number;
      executeClaimPriorTheCall: boolean;
    }) {
      const context: TestContext = await setUpFixture(deployAndConfigureContracts);
      await proveTx(context.balanceTrackerMock.setBalanceRecords(user.address, balanceRecords));
      await proveTx(context.balanceTrackerMock.setDayAndTime(currentDay, currentTime));
      const claimRequest: ClaimRequest = { ...claimRequestBase };
      const expectedClaimAllResult: ClaimResult = defineExpectedClaimAllResult(claimRequest);
      if (props.executeClaimPriorTheCall) {
        claimRequest.amount = roundDown(expectedClaimAllResult.primaryYield.div(2));
        await proveTx(await context.yieldStreamer.connect(user).claim(claimRequest.amount));
      }
      const claimState: ClaimState = await context.yieldStreamer.getLastClaimDetails(user.address);

      const balanceWithYieldByDaysRequest: BalanceWithYieldByDaysRequest = { ...balanceWithYieldByDaysRequestBase };
      const nextClaimDay: number = claimState.day || YIELD_STREAMER_INIT_DAY;
      balanceWithYieldByDaysRequest.firstYieldDay = nextClaimDay;
      balanceWithYieldByDaysRequest.claimDebit = claimState.debit;
      balanceWithYieldByDaysRequest.dayFrom = nextClaimDay + props.firstDayRangeRelativeToNexClaimDay;
      balanceWithYieldByDaysRequest.dayTo = nextClaimDay + props.lastDayRangeRelativeToNexClaimDay;

      const expectedBalanceWithYieldByDays: BigNumber[] =
        defineExpectedBalanceWithYieldByDays(balanceWithYieldByDaysRequest);
      const actualBalanceWithYieldByDays = await context.yieldStreamer.getDailyBalancesWithYield(
        user.address,
        balanceWithYieldByDaysRequest.dayFrom,
        balanceWithYieldByDaysRequest.dayTo
      );
      expect(actualBalanceWithYieldByDays).to.deep.equal(expectedBalanceWithYieldByDays);
    }

    describe("Executes as expected if", async () => {
      describe("There was a claim made by the account and", async () => {
        it("Argument 'fromDay' is prior the next claim day and `toDay` is after the next claim day", async () => {
          await checkGetDailyBalancesWithYield({
            firstDayRangeRelativeToNexClaimDay: -(LOOK_BACK_PERIOD_LENGTH + 1),
            lastDayRangeRelativeToNexClaimDay: +(LOOK_BACK_PERIOD_LENGTH + 1),
            executeClaimPriorTheCall: true
          });
        });
        it("Arguments 'fromDay', `toDay` are both prior the next claim day", async () => {
          await checkGetDailyBalancesWithYield({
            firstDayRangeRelativeToNexClaimDay: -(LOOK_BACK_PERIOD_LENGTH + 1),
            lastDayRangeRelativeToNexClaimDay: -1,
            executeClaimPriorTheCall: true
          });
        });
        it("Arguments 'fromDay', `toDay` are both after the next claim day", async () => {
          await checkGetDailyBalancesWithYield({
            firstDayRangeRelativeToNexClaimDay: +1,
            lastDayRangeRelativeToNexClaimDay: +(LOOK_BACK_PERIOD_LENGTH + 1),
            executeClaimPriorTheCall: true
          });
        });
        it("Arguments 'fromDay', `toDay` are both equal to the next claim day", async () => {
          await checkGetDailyBalancesWithYield({
            firstDayRangeRelativeToNexClaimDay: 0,
            lastDayRangeRelativeToNexClaimDay: 0,
            executeClaimPriorTheCall: true
          });
        });
      });
      describe("There were no claims made by the account and", async () => {
        it("Argument 'fromDay' is prior the next claim day and `toDay` is after the next claim day", async () => {
          await checkGetDailyBalancesWithYield({
            firstDayRangeRelativeToNexClaimDay: -(YIELD_STREAMER_INIT_DAY - BALANCE_TRACKER_INIT_DAY),
            lastDayRangeRelativeToNexClaimDay: +10,
            executeClaimPriorTheCall: false
          });
        });
        it("Arguments 'fromDay', `toDay` are both prior the next claim day", async () => {
          await checkGetDailyBalancesWithYield({
            firstDayRangeRelativeToNexClaimDay: -1,
            lastDayRangeRelativeToNexClaimDay: -1,
            executeClaimPriorTheCall: false
          });
        });
        it("Arguments 'fromDay', `toDay` are both after the next claim day", async () => {
          await checkGetDailyBalancesWithYield({
            firstDayRangeRelativeToNexClaimDay: +1,
            lastDayRangeRelativeToNexClaimDay: +1,
            executeClaimPriorTheCall: false
          });
        });
        it("Arguments 'fromDay', `toDay` are both equal to the next claim day", async () => {
          await checkGetDailyBalancesWithYield({
            firstDayRangeRelativeToNexClaimDay: 0,
            lastDayRangeRelativeToNexClaimDay: 0,
            executeClaimPriorTheCall: false
          });
        });
      });
    });

    describe("Is reverted if", async () => {
      it("The 'to' day is prior the 'from' day", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        await expect(
          context.yieldStreamer.getDailyBalancesWithYield(
            user.address,
            balanceWithYieldByDaysRequestBase.dayFrom,
            balanceWithYieldByDaysRequestBase.dayFrom - 1
          )
        ).to.revertedWithCustomError(context.yieldStreamer, REVERT_ERROR_TO_DAY_PRIOR_FROM_DAY);
      });
    });
  });

  // This section is only to achieve 100% coverage of the balance tracker mock contract
  describe("Function 'getDailyBalances()'", async () => {
    describe("Is reverted if", async () => {
      it("The 'from' day is prior the init day", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        await expect(
          context.yieldStreamer.getDailyBalances(
            user.address,
            BALANCE_TRACKER_INIT_DAY - 1,
            BALANCE_TRACKER_INIT_DAY
          )
        ).to.reverted;
      });

      it("The 'to' day is prior the 'from' day", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        await expect(
          context.yieldStreamer.getDailyBalances(
            user.address,
            YIELD_STREAMER_INIT_DAY,
            YIELD_STREAMER_INIT_DAY - 1
          )
        ).to.reverted;
      });

      it("There are no balance records", async () => {
        const context: TestContext = await setUpFixture(deployAndConfigureContracts);
        await expect(
          context.yieldStreamer.getDailyBalances(
            user.address,
            YIELD_STREAMER_INIT_DAY,
            YIELD_STREAMER_INIT_DAY
          )
        ).to.reverted;
      });
    });
  });

  describe("Function 'dayAndTime()'", async () => {
    it("Executes as expected", async () => {
      const context: TestContext = await setUpFixture(deployAndConfigureContracts);
      const day = 123456789;
      const time = 987654321;
      await proveTx(context.balanceTrackerMock.setDayAndTime(day, time));
      expect(await context.yieldStreamer.dayAndTime()).to.deep.equal([day, time]);
    });
  });
});
