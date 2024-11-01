import { expect } from "chai";
import { ethers, network, upgrades } from "hardhat";
import { Contract, ContractFactory } from "ethers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

const ROUND_FACTOR = 10000;
const DAY_IN_SECONDS = 86400n;

const REVERT_ERROR_IF_YIELD_RATE_ARRAY_IS_EMPTY = "YieldStreamer_YieldRateArrayIsEmpty";
const REVERT_ERROR_IF_TIME_RANGE_IS_INVALID = "YieldStreamer_TimeRangeIsInvalid";

interface RateTier {
  rate: bigint;
  cap: bigint;
}

interface YieldRate {
  tiers: RateTier[];
  effectiveDay: bigint;
}

interface YieldResult {
  firstDayPartialYield: bigint;
  fullDaysYield: bigint;
  lastDayPartialYield: bigint;
}

interface AccruePreview {
  fromTimestamp: bigint;
  toTimestamp: bigint;
  balance: bigint;
  streamYieldBefore: bigint;
  accruedYieldBefore: bigint;
  streamYieldAfter: bigint;
  accruedYieldAfter: bigint;
  rates: YieldRate[];
  results: YieldResult[];
}

interface ClaimPreview {
  yield: bigint;
  fee: bigint;
  timestamp: bigint;
  balance: bigint;
  rates: bigint[];
  caps: bigint[];
}

async function setUpFixture<T>(func: () => Promise<T>): Promise<T> {
  if (network.name === "hardhat") {
    // Use Hardhat's snapshot functionality for faster test execution.
    return loadFixture(func);
  } else {
    // Directly execute the function if not on Hardhat network.
    return func();
  }
}

describe("YieldStreamerV2Testable", function () {
  let yieldStreamerTestableFactory: ContractFactory;

  before(async function () {
    yieldStreamerTestableFactory = await ethers.getContractFactory("YieldStreamerV2Testable");
  });

  async function deployContracts(): Promise<{ yieldStreamerTestable: Contract; tokenMock: Contract }> {
    const tokenMockFactory = await ethers.getContractFactory("ERC20TokenMock");
    const tokenMock = await tokenMockFactory.deploy("Mock Token", "MTK");
    await tokenMock.waitForDeployment();

    const yieldStreamerTestable: Contract = await upgrades.deployProxy(yieldStreamerTestableFactory, [
      tokenMock.target
    ]);
    await yieldStreamerTestable.waitForDeployment();

    return { yieldStreamerTestable, tokenMock };
  }

  function roundDown(amount: bigint): bigint {
    return (amount / BigInt(ROUND_FACTOR)) * BigInt(ROUND_FACTOR);
  }

  function roundUp(amount: bigint): bigint {
    const roundedAmount = roundDown(amount);
    if (roundedAmount < amount) {
      return roundedAmount + BigInt(ROUND_FACTOR);
    }
    return roundedAmount;
  }

  async function addSampleYieldRates(
    yieldStreamerTestable: Contract,
    groupId: number,
    count: number
  ): Promise<YieldRate[]> {
    const rates: YieldRate[] = [];

    // Build the yield rates array.
    for (let i = 0; i < count; i++) {
      rates.push({
        tiers: [
          {
            rate: BigInt(i),
            cap: BigInt(i)
          }
        ],
        effectiveDay: BigInt(i)
      });
    }

    // Add yield rates to the contract.
    for (const rate of rates) {
      const ratesArray = rate.tiers.map(tier => tier.rate);
      const capsArray = rate.tiers.map(tier => tier.cap);
      await yieldStreamerTestable.addYieldRate(groupId, rate.effectiveDay, ratesArray, capsArray);
    }

    return rates;
  }

  // Helper function to add yield rates to the contract
  async function addYieldRatesToContract(yieldStreamerTestable: Contract, groupId: number, rates: YieldRate[]) {
    for (const rate of rates) {
      const ratesArray = rate.tiers.map(tier => tier.rate);
      const capsArray = rate.tiers.map(tier => tier.cap);
      await yieldStreamerTestable.addYieldRate(groupId, rate.effectiveDay, ratesArray, capsArray);
    }
  }

  function normalizeYieldRates(rates: any[]): YieldRate[] {
    return rates.map((rate: any) => ({
      effectiveDay: BigInt(rate[1]),
      tiers: rate[0].map((tier: any) => ({
        rate: BigInt(tier[0]),
        cap: BigInt(tier[1])
      }))
    }));
  }

  describe.only("Function 'inRangeYieldRates()'", function () {
    let yieldStreamerTestable: Contract;

    beforeEach(async function () {
      const contracts = await setUpFixture(deployContracts);
      yieldStreamerTestable = contracts.yieldStreamerTestable;
    });

    it("Should return indices (0, 0) when rates array has only one item", async function () {
      const groupId = 0;
      // Add one yield rate with effectiveDay 0 (it's a rule that the first rate has to be with effectiveDay 0)
      const rates: YieldRate[] = [
        {
          tiers: [{ rate: 1000n, cap: 1000n }],
          effectiveDay: 0n
        }
      ];

      await addYieldRatesToContract(yieldStreamerTestable, groupId, rates);

      const fromTimestamp = 100n;
      const toTimestamp = 200n;

      // Call inRangeYieldRates function
      const [startIndex, endIndex] = await yieldStreamerTestable.inRangeYieldRates(groupId, fromTimestamp, toTimestamp);

      expect(startIndex).to.equal(0);
      expect(endIndex).to.equal(0);
    });

    // Testing with varying fromTimestamp and toTimestamp values, and multiple rates

    const firstRateEffectiveDay = 0n;
    const secondRateEffectiveDay = 10n;
    const thirdRateEffectiveDay = 20n;

    const rates = [
      {
        tiers: [{ rate: 1000n, cap: 1000n }],
        effectiveDay: firstRateEffectiveDay
      },
      {
        tiers: [{ rate: 1000n, cap: 1000n }],
        effectiveDay: secondRateEffectiveDay
      },
      {
        tiers: [{ rate: 1000n, cap: 1000n }],
        effectiveDay: thirdRateEffectiveDay
      }
    ];

    const testCases = [
      // Case 1:
      // - fromTimestamp is 2s before the second rate effective day
      // - toTimestamp is 1s before the second rate effective day
      // Expected: startIndex = 0, endIndex = 0
      {
        fromTimestamp: -2n + secondRateEffectiveDay * DAY_IN_SECONDS,
        toTimestamp: -1n + secondRateEffectiveDay * DAY_IN_SECONDS,
        expectedStartIndex: 0,
        expectedEndIndex: 0
      },
      // Case 2:
      // - fromTimestamp is 1s before the second rate effective day
      // - toTimestamp is exactly on the second rate effective day
      // Expected: startIndex = 0, endIndex = 0
      {
        fromTimestamp: -1n + secondRateEffectiveDay * DAY_IN_SECONDS,
        toTimestamp: 0n + secondRateEffectiveDay * DAY_IN_SECONDS,
        expectedStartIndex: 0,
        expectedEndIndex: 0
      },
      // Case 3:
      // - fromTimestamp is 1s before the second rate effective day
      // - toTimestamp is 1s after the second rate effective day
      // Expected: startIndex = 0, endIndex = 1
      {
        fromTimestamp: -1n + secondRateEffectiveDay * DAY_IN_SECONDS,
        toTimestamp: 1n + secondRateEffectiveDay * DAY_IN_SECONDS,
        expectedStartIndex: 0,
        expectedEndIndex: 1
      },
      // Case 4:
      // - fromTimestamp is 1s before the second rate effective day
      // - toTimestamp is 1s before the third rate effective day
      // Expected: startIndex = 0, endIndex = 1
      {
        fromTimestamp: -1n + secondRateEffectiveDay * DAY_IN_SECONDS,
        toTimestamp: -1n + thirdRateEffectiveDay * DAY_IN_SECONDS,
        expectedStartIndex: 0,
        expectedEndIndex: 1
      },
      // Case 5:
      // - fromTimestamp is 1s before the second rate effective day
      // - toTimestamp is exactly on the third rate effective day
      // Expected: startIndex = 0, endIndex = 1
      {
        fromTimestamp: -1n + secondRateEffectiveDay * DAY_IN_SECONDS,
        toTimestamp: 0n + thirdRateEffectiveDay * DAY_IN_SECONDS,
        expectedStartIndex: 0,
        expectedEndIndex: 1
      },
      // Case 6:
      // - fromTimestamp is 1s before the second rate effective day
      // - toTimestamp is 1s after the third rate effective day
      // Expected: startIndex = 0, endIndex = 2
      {
        fromTimestamp: -1n + secondRateEffectiveDay * DAY_IN_SECONDS,
        toTimestamp: 1n + thirdRateEffectiveDay * DAY_IN_SECONDS,
        expectedStartIndex: 0,
        expectedEndIndex: 2
      },
      // Case 7:
      // - fromTimestamp is exactly on the second rate effective day
      // - toTimestamp is 1s after the third rate effective day
      // Expected: startIndex = 1, endIndex = 2
      {
        fromTimestamp: 0n + secondRateEffectiveDay * DAY_IN_SECONDS,
        toTimestamp: 1n + thirdRateEffectiveDay * DAY_IN_SECONDS,
        expectedStartIndex: 1,
        expectedEndIndex: 2
      },
      // Case 8:
      // - fromTimestamp is 1s after the second rate effective day
      // - toTimestamp is 1s after the third rate effective day
      // Expected: startIndex = 1, endIndex = 2
      {
        fromTimestamp: 1n + secondRateEffectiveDay * DAY_IN_SECONDS,
        toTimestamp: 1n + thirdRateEffectiveDay * DAY_IN_SECONDS,
        expectedStartIndex: 1,
        expectedEndIndex: 2
      },
      // Case 9:
      // - fromTimestamp is 1s before the third rate effective day
      // - toTimestamp is 1s after the third rate effective day
      // Expected: startIndex = 1, endIndex = 2
      {
        fromTimestamp: -1n + thirdRateEffectiveDay * DAY_IN_SECONDS,
        toTimestamp: 1n + thirdRateEffectiveDay * DAY_IN_SECONDS,
        expectedStartIndex: 1,
        expectedEndIndex: 2
      },
      // Case 10:
      // - fromTimestamp is exactly on the third rate effective day
      // - toTimestamp is 1s after the third rate effective day
      // Expected: startIndex = 2, endIndex = 2
      {
        fromTimestamp: 0n + thirdRateEffectiveDay * DAY_IN_SECONDS,
        toTimestamp: 1n + thirdRateEffectiveDay * DAY_IN_SECONDS,
        expectedStartIndex: 2,
        expectedEndIndex: 2
      },
      // Case 11:
      // - fromTimestamp is 1s after the third rate effective day
      // - toTimestamp is 2s after the third rate effective day
      // Expected: startIndex = 2, endIndex = 2
      {
        fromTimestamp: 1n + thirdRateEffectiveDay * DAY_IN_SECONDS,
        toTimestamp: 2n + thirdRateEffectiveDay * DAY_IN_SECONDS,
        expectedStartIndex: 2,
        expectedEndIndex: 2
      },
      // Case 12:
      // - fromTimestamp is exactly on the second rate effective day
      // - toTimestamp is 1s before the third rate effective day
      // Expected: startIndex = 1, endIndex = 1
      {
        fromTimestamp: 0n + secondRateEffectiveDay * DAY_IN_SECONDS,
        toTimestamp: -1n + thirdRateEffectiveDay * DAY_IN_SECONDS,
        expectedStartIndex: 1,
        expectedEndIndex: 1
      }
    ];

    testCases.forEach(({ fromTimestamp, toTimestamp, expectedStartIndex, expectedEndIndex }, index) => {
      it(`Testing with varying fromTimestamp and toTimestamp values, and multiple rates. Test case ${index + 1}`, async function () {
        const groupId = index; // Unique groupId for each test case

        await addYieldRatesToContract(yieldStreamerTestable, groupId, rates);

        // Call inRangeYieldRates function
        const [startIndex, endIndex] = await yieldStreamerTestable.inRangeYieldRates(
          groupId,
          fromTimestamp,
          toTimestamp
        );

        expect(startIndex).to.equal(expectedStartIndex);
        expect(endIndex).to.equal(expectedEndIndex);
      });
    });

    it("Should revert when there are no yield rates in the array", async function () {
      const groupId = 0;
      await expect(yieldStreamerTestable.inRangeYieldRates(groupId, 100n, 200n)).to.be.revertedWithCustomError(
        yieldStreamerTestable,
        REVERT_ERROR_IF_YIELD_RATE_ARRAY_IS_EMPTY
      );
    });

    it("Should revert when the fromTimestamp is greater than the toTimestamp", async function () {
      const groupId = 0;
      await addSampleYieldRates(yieldStreamerTestable, groupId, 2);
      await expect(yieldStreamerTestable.inRangeYieldRates(groupId, 101n, 100n)).to.be.revertedWithCustomError(
        yieldStreamerTestable,
        REVERT_ERROR_IF_TIME_RANGE_IS_INVALID
      );
    });

    it("Should revert when the fromTimestamp is equal to the toTimestamp", async function () {
      const groupId = 0;
      await addSampleYieldRates(yieldStreamerTestable, groupId, 2);
      await expect(yieldStreamerTestable.inRangeYieldRates(groupId, 100n, 100n)).to.be.revertedWithCustomError(
        yieldStreamerTestable,
        REVERT_ERROR_IF_TIME_RANGE_IS_INVALID
      );
    });
  });

  describe("Function 'aggregateYield()'", function () {
    it("Should return (0, 0) when yieldResults is empty", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);

      // Call the aggregateYield function with an empty array
      const yieldResults: YieldResult[] = [];
      const [accruedYield, streamYield] = await yieldStreamerTestable.aggregateYield(yieldResults);

      expect(accruedYield).to.equal(0);
      expect(streamYield).to.equal(0);
    });

    it("Should correctly handle a single YieldResult", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);

      // Single YieldResult with sample values
      const yieldResult: YieldResult = {
        firstDayPartialYield: BigInt(100),
        fullDaysYield: BigInt(200),
        lastDayPartialYield: BigInt(50)
      };

      const yieldResults: YieldResult[] = [yieldResult];

      // Expected values based on the updated function logic
      const expectedAccruedYield = yieldResult.firstDayPartialYield + yieldResult.fullDaysYield;
      const expectedStreamYield = yieldResult.lastDayPartialYield;

      const [accruedYield, streamYield] = await yieldStreamerTestable.aggregateYield(yieldResults);

      expect(accruedYield).to.equal(expectedAccruedYield);
      expect(streamYield).to.equal(expectedStreamYield);
    });

    it("Should correctly aggregate multiple YieldResults", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);

      const yieldResults: YieldResult[] = [
        {
          firstDayPartialYield: BigInt(100),
          fullDaysYield: BigInt(200),
          lastDayPartialYield: BigInt(50)
        },
        {
          firstDayPartialYield: BigInt(80),
          fullDaysYield: BigInt(150),
          lastDayPartialYield: BigInt(40)
        },
        {
          firstDayPartialYield: BigInt(70),
          fullDaysYield: BigInt(120),
          lastDayPartialYield: BigInt(30)
        }
      ];

      // Calculate expected accruedYield according to the updated function logic
      const expectedAccruedYield =
        // First period: include firstDayPartialYield, fullDaysYield, and lastDayPartialYield
        yieldResults[0].firstDayPartialYield +
        yieldResults[0].fullDaysYield +
        yieldResults[0].lastDayPartialYield +
        // Second period: include firstDayPartialYield, fullDaysYield, and lastDayPartialYield
        yieldResults[1].firstDayPartialYield +
        yieldResults[1].fullDaysYield +
        yieldResults[1].lastDayPartialYield +
        // Third period: include firstDayPartialYield and fullDaysYield (exclude lastDayPartialYield)
        yieldResults[2].firstDayPartialYield +
        yieldResults[2].fullDaysYield;

      const expectedStreamYield = yieldResults[yieldResults.length - 1].lastDayPartialYield;
      const [accruedYield, streamYield] = await yieldStreamerTestable.aggregateYield(yieldResults);

      expect(accruedYield).to.equal(expectedAccruedYield);
      expect(streamYield).to.equal(expectedStreamYield);
    });
  });

  describe("Function to work with timestamps", function () {
    it("Should return the next day as expected", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);

      const timestamps = [
        BigInt(0),
        BigInt(1),
        BigInt(50),
        BigInt(86399),
        BigInt(86400),
        BigInt(86401),
        BigInt(2 * 86400),
        BigInt(3 * 86400 + 12345),
        BigInt(1660135722n)
      ];

      for (const ts of timestamps) {
        const nextDay = await yieldStreamerTestable.nextDay(ts);
        const expectedNextDay = ts - (ts % BigInt(86400)) + BigInt(86400);
        expect(nextDay).to.equal(expectedNextDay);
      }
    });

    it("Should return the effective day as expected", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);

      const timestamps = [
        BigInt(0),
        BigInt(1),
        BigInt(50),
        BigInt(86399),
        BigInt(86400),
        BigInt(86401),
        BigInt(2 * 86400),
        BigInt(3 * 86400 + 12345),
        BigInt(1660135722n)
      ];

      for (const ts of timestamps) {
        const effectiveDay = await yieldStreamerTestable.effectiveDay(ts);
        const expectedDay = ts / BigInt(86400);
        expect(effectiveDay).to.equal(expectedDay);
      }
    });

    it("Should return the remaining seconds as expected", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);

      const timestamps = [
        BigInt(0),
        BigInt(1),
        BigInt(50),
        BigInt(86399),
        BigInt(86400),
        BigInt(86401),
        BigInt(2 * 86400),
        BigInt(3 * 86400 + 12345),
        BigInt(1660135722n)
      ];

      for (const ts of timestamps) {
        const remainingSeconds = await yieldStreamerTestable.remainingSeconds(ts);
        const expectedRemainingSeconds = ts % BigInt(86400);
        expect(remainingSeconds).to.equal(expectedRemainingSeconds);
      }
    });

    it("Should return the effective timestamp as expected", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);

      const timestamps = [
        BigInt(0),
        BigInt(1),
        BigInt(50),
        BigInt(86399),
        BigInt(86400),
        BigInt(86401),
        BigInt(2 * 86400),
        BigInt(3 * 86400 + 12345),
        BigInt(1660135722n)
      ];

      for (const ts of timestamps) {
        const effectiveTimestamp = await yieldStreamerTestable.effectiveTimestamp(ts);
        const expectedEffectiveTimestamp = (ts / BigInt(86400)) * BigInt(86400);
        expect(effectiveTimestamp).to.equal(expectedEffectiveTimestamp);
      }
    });
  });

  describe("Function 'truncateArray()'", function () {
    it("Should return the full array when startIndex is 0 and endIndex is rates.length - 1", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);
      const groupId = 0;
      const rates = await addSampleYieldRates(yieldStreamerTestable, groupId, 5);
      const truncatedRatesRaw = await yieldStreamerTestable.truncateArray(groupId, 0, rates.length - 1);
      const truncatedRates = normalizeYieldRates(truncatedRatesRaw);
      expect(truncatedRates).to.deep.equal(rates);
    });

    it("Should return a truncated array when startIndex and endIndex are different", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);
      const groupId = 0;
      const rates = await addSampleYieldRates(yieldStreamerTestable, groupId, 5);
      const truncatedRatesRaw = await yieldStreamerTestable.truncateArray(groupId, 1, 3);
      const truncatedRates = normalizeYieldRates(truncatedRatesRaw);
      expect(truncatedRates).to.deep.equal(rates.slice(1, 4));
    });

    it("Should return a single element when startIndex and endIndex are the same (multiple rates in array)", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);
      const groupId = 0;
      const rates = await addSampleYieldRates(yieldStreamerTestable, groupId, 5);
      const truncatedRatesRaw = await yieldStreamerTestable.truncateArray(groupId, 2, 2);
      const truncatedRates = normalizeYieldRates(truncatedRatesRaw);
      expect(truncatedRates.length).to.equal(1);
      expect(truncatedRates[0]).to.deep.equal(rates[2]);
    });

    it("Should return a single element when startIndex and endIndex are the same (single rate in array)", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);
      const groupId = 0;
      const rates = await addSampleYieldRates(yieldStreamerTestable, groupId, 1);
      const truncatedRatesRaw = await yieldStreamerTestable.truncateArray(groupId, 0, 0);
      const truncatedRates = normalizeYieldRates(truncatedRatesRaw);
      expect(truncatedRates.length).to.equal(1);
      expect(truncatedRates[0]).to.deep.equal(rates[0]);
    });

    it("Should revert when startIndex is greater than endIndex", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);
      const groupId = 0;
      await addSampleYieldRates(yieldStreamerTestable, groupId, 5);
      await expect(yieldStreamerTestable.truncateArray(groupId, 3, 2)).to.be.revertedWithPanic(0x11); // Arithmetic operation overflowed outside of an unchecked block
    });

    it("Should revert when startIndex is out of bounds", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);
      const groupId = 0;
      await addSampleYieldRates(yieldStreamerTestable, groupId, 5);
      await expect(yieldStreamerTestable.truncateArray(groupId, 5, 5)).to.be.revertedWithPanic(0x32); // Array accessed at an out-of-bounds or negative index
    });

    it("Should revert when endIndex is out of bounds", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);
      const groupId = 0;
      await addSampleYieldRates(yieldStreamerTestable, groupId, 5);
      await expect(yieldStreamerTestable.truncateArray(groupId, 5, 5)).to.be.revertedWithPanic(0x32); // Array accessed at an out-of-bounds or negative index
    });

    it("Should revert when rates array is empty", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);
      const groupId = 0;
      await expect(yieldStreamerTestable.truncateArray(groupId, 0, 0)).to.be.revertedWithPanic(0x32); // Array accessed at an out-of-bounds or negative index
    });
  });

  describe("Function 'roundDown()'", async () => {
    it("Should round down as expected", async () => {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);
      expect(await yieldStreamerTestable.roundDown(BigInt("0"))).to.equal(BigInt("0"));
      expect(await yieldStreamerTestable.roundDown(BigInt("10000000"))).to.equal(BigInt("10000000"));
      expect(await yieldStreamerTestable.roundDown(BigInt("10000001"))).to.equal(BigInt("10000000"));
      expect(await yieldStreamerTestable.roundDown(BigInt("10009999"))).to.equal(BigInt("10000000"));
      expect(await yieldStreamerTestable.roundDown(BigInt("0"))).to.equal(roundDown(BigInt("0")));
      expect(await yieldStreamerTestable.roundDown(BigInt("10000000"))).to.equal(roundDown(BigInt("10000000")));
      expect(await yieldStreamerTestable.roundDown(BigInt("10000001"))).to.equal(roundDown(BigInt("10000001")));
      expect(await yieldStreamerTestable.roundDown(BigInt("10009999"))).to.equal(roundDown(BigInt("10009999")));
    });
  });

  describe("Function 'roundUp()'", async () => {
    it("Should round up as expected", async () => {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);
      expect(await yieldStreamerTestable.roundUp(BigInt("0"))).to.equal(BigInt("0"));
      expect(await yieldStreamerTestable.roundUp(BigInt("10000000"))).to.equal(BigInt("10000000"));
      expect(await yieldStreamerTestable.roundUp(BigInt("10000001"))).to.equal(BigInt("10010000"));
      expect(await yieldStreamerTestable.roundUp(BigInt("10009999"))).to.equal(BigInt("10010000"));
      expect(await yieldStreamerTestable.roundUp(BigInt("0"))).to.equal(roundUp(BigInt("0")));
      expect(await yieldStreamerTestable.roundUp(BigInt("10000000"))).to.equal(roundUp(BigInt("10000000")));
      expect(await yieldStreamerTestable.roundUp(BigInt("10000001"))).to.equal(roundUp(BigInt("10000001")));
      expect(await yieldStreamerTestable.roundUp(BigInt("10009999"))).to.equal(roundUp(BigInt("10009999")));
    });
  });

  describe("Function 'map()'", async () => {
    it("Should map as expected", async () => {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);

      // Create an AccruePreview object with sample data.
      const accruePreview: AccruePreview = {
        fromTimestamp: BigInt("10000000"),
        toTimestamp: BigInt("20000000"),
        balance: BigInt("30000000"),
        streamYieldBefore: BigInt("199999"),
        accruedYieldBefore: BigInt("299999"),
        streamYieldAfter: BigInt("499999"),
        accruedYieldAfter: BigInt("399999"),
        rates: [
          {
            tiers: [
              {
                rate: BigInt("100"),
                cap: BigInt("100")
              },
              {
                rate: BigInt("200"),
                cap: BigInt("200")
              }
            ],
            effectiveDay: BigInt("1")
          },
          {
            tiers: [
              {
                rate: BigInt("300"),
                cap: BigInt("300")
              },
              {
                rate: BigInt("400"),
                cap: BigInt("400")
              }
            ],
            effectiveDay: BigInt("9")
          }
        ],
        results: [
          {
            firstDayPartialYield: BigInt("10"),
            fullDaysYield: BigInt("20"),
            lastDayPartialYield: BigInt("30")
          },
          {
            firstDayPartialYield: BigInt("40"),
            fullDaysYield: BigInt("50"),
            lastDayPartialYield: BigInt("60")
          }
        ]
      };

      // Call the map function.
      const claimPreviewRaw: ClaimPreview = await yieldStreamerTestable.map(accruePreview);

      // Set the expected values.
      const expectedClaimPreview: ClaimPreview = {
        yield: roundDown(accruePreview.accruedYieldAfter + accruePreview.streamYieldAfter),
        fee: BigInt("0"),
        timestamp: BigInt("0"),
        balance: accruePreview.balance,
        rates: accruePreview.rates[accruePreview.rates.length - 1].tiers.map(tier => tier.rate),
        caps: accruePreview.rates[accruePreview.rates.length - 1].tiers.map(tier => tier.cap)
      };

      // Verify the return values.
      expect(expectedClaimPreview.yield).to.equal(claimPreviewRaw.yield);
      expect(expectedClaimPreview.fee).to.equal(claimPreviewRaw.fee);
      expect(expectedClaimPreview.timestamp).to.equal(claimPreviewRaw.timestamp);
      expect(expectedClaimPreview.balance).to.equal(claimPreviewRaw.balance);
      expect(expectedClaimPreview.rates).to.deep.equal(claimPreviewRaw.rates);
      expect(expectedClaimPreview.caps).to.deep.equal(claimPreviewRaw.caps);
    });
  });
});
