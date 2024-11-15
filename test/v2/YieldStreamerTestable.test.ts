import { expect } from "chai";
import { ethers, network, upgrades } from "hardhat";
import { Contract, ContractFactory } from "ethers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

const RATE_FACTOR = 1000000000000n;
const ROUND_FACTOR = 10000n;
const DAY = 86400n;
const HOUR = 3600n;
const INITIAL_DAY_INDEX = 21000n;

const REVERT_ERROR_IF_YIELD_RATE_ARRAY_IS_EMPTY = "YieldStreamer_YieldRateArrayIsEmpty";
const REVERT_ERROR_IF_TIME_RANGE_IS_INVALID = "YieldStreamer_TimeRangeIsInvalid";
interface YieldState {
  flags: bigint;
  streamYield: bigint;
  accruedYield: bigint;
  lastUpdateTimestamp: bigint;
  lastUpdateBalance: bigint;
}

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
  tieredFirstDayPartialYield: bigint[];
  tieredFullDaysYield: bigint[];
  tieredLastDayPartialYield: bigint[];
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
    return (amount / ROUND_FACTOR) * ROUND_FACTOR;
  }

  function roundUp(amount: bigint): bigint {
    const roundedAmount = roundDown(amount);
    if (roundedAmount < amount) {
      return roundedAmount + ROUND_FACTOR;
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
    for (let i = 0n; i < count; i++) {
      rates.push({
        tiers: [
          {
            rate: i,
            cap: i
          }
        ],
        effectiveDay: i
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
      effectiveDay: rate[1],
      tiers: rate[0].map((tier: any) => ({
        rate: tier[0],
        cap: tier[1]
      }))
    }));
  }

  function normalizeYieldResult(result: any): [bigint, bigint[]] {
    return [result[0], result[1]];
  }

  function simpleYield(amount: bigint, rate: bigint, elapsedSeconds: bigint): bigint {
    return (amount * rate * elapsedSeconds) / (DAY * RATE_FACTOR);
  }

  describe("Function 'getAccruePreview()'", function () {
    let yieldStreamerTestable: Contract;

    beforeEach(async function () {
      const contracts = await setUpFixture(deployContracts);
      yieldStreamerTestable = contracts.yieldStreamerTestable;
    });

    interface GetAccruePreviewTestCase {
      description: string;
      state: YieldState;
      rates: YieldRate[];
      currentTimestamp: bigint;
      expected: AccruePreview;
    }

    const testCases: GetAccruePreviewTestCase[] = [
      {
        description: "One yield rate",
        state: {
          lastUpdateTimestamp: INITIAL_DAY_INDEX * DAY + HOUR * 6n,
          lastUpdateBalance: 3000000n,
          streamYield: 1000000n,
          accruedYield: 2000000n,
          flags: 0n
        },
        rates: [
          {
            tiers: [
              { rate: RATE_FACTOR / 1000n, cap: 0n } // - 0.1% rate, no cap
            ],
            effectiveDay: 0n
          },
          {
            tiers: [
              { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
            ],
            effectiveDay: INITIAL_DAY_INDEX
          }
        ],
        currentTimestamp: INITIAL_DAY_INDEX * DAY + DAY * 3n + HOUR * 6n,
        expected: {
          fromTimestamp: INITIAL_DAY_INDEX * DAY + HOUR * 6n,
          toTimestamp: INITIAL_DAY_INDEX * DAY + DAY * 3n + HOUR * 6n,
          balance: 3000000n,
          streamYieldBefore: 1000000n,
          accruedYieldBefore: 2000000n,
          accruedYieldAfter:
            2000000n + // -------------- Initial accrued yield
            1000000n + // -------------- Initial stream yield
            60000n + // ---------------- FPD yield
            90600n + // ---------------- FD1 yield
            91506n, // ----------------- FD2 yield
          streamYieldAfter: 23105n, // - LPD yield
          rates: [
            {
              tiers: [
                { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
                { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
                { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
              ],
              effectiveDay: INITIAL_DAY_INDEX
            }
          ],
          results: [
            {
              firstDayPartialYield:
                // FPD Total: 60000
                1000000n + // - Stream yield
                22500n + // --- T1: 3% on 1000000 for 18 hours (Initial balance)
                15000n + // --- T2: 2% on 2000000 for 18 hours (Initial balance)
                22500n, // ---- T3: 1% on 3000000 for 18 hours (Initial balance)
              fullDaysYield:
                // FD1 Total: 90600
                30000n + // - T1: 3% on 1000000 for 1 day (Initial balance)
                20000n + // - T2: 2% on 1000000 for 1 day (Initial balance)
                30000n + // - T3: 1% on 3000000 for 1 day (Initial balance)
                10000n + // - T3: 1% on 1000000 for 1 day (Stream yield)
                600n + // --- T3: 1% on 60000 for 1 day (FPD yield)
                // ------
                // FD2 Total: 91506
                30000n + // - T1: 3% on 1000000 for 1 day (Initial balance)
                20000n + // - T2: 2% on 1000000 for 1 day (Initial balance)
                30000n + // - T3: 1% on 3000000 for 1 day (Initial balance)
                10000n + // - T3: 1% on 1000000 for 1 day (Stream yield)
                600n + // --- T3: 1% on 60000 for 1 day (FPD yield)
                906n, // ---- T3: 1% on 90600 for 1 day (FD1 yield)
              lastDayPartialYield:
                // LPD Total: 23105
                7500n + // - T1: 3% on 1000000 for 6 hours (Initial balance)
                5000n + // - T2: 2% on 1000000 for 6 hours (Initial balance)
                7500n + // - T3: 1% on 3000000 for 6 hours (Initial balance)
                2500n + // - T3: 1% on 1000000 for 6 hours (Stream yield)
                605n, // --- T3: 1% on 242106 for 6 hours (Accrued yield)
              tieredFirstDayPartialYield: [
                // FPD Total: 60000
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n * 18n), // - FPD T1: 22500
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n * 18n), // - FPD T2: 15000
                simpleYield(3000000n, (RATE_FACTOR / 100n) * 1n, 3600n * 18n) // -- FPD T3: 22500
              ],
              tieredFullDaysYield: [
                // FD1 + FD2 Total: 182106
                // FD1 Total: 30000 + 20000 + 40600 = 90600
                // FD2 Total: 30000 + 20000 + 41506 = 91506
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n) + // - FD1 T1: 30000
                  simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n), // -- FD2 T1: 30000
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n) + // - FD1 T2: 20000
                  simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n), // -- FD2 T2: 20000
                simpleYield(
                  3000000n + // - Initial balance
                    1000000n + // - Stream yield
                    60000n, // ---- FPD yield
                  (RATE_FACTOR / 100n) * 1n,
                  86400n
                ) + // -------------------------------------------------------- FD1 T3: 40600
                  simpleYield(
                    3000000n + // - Initial balance
                      1000000n + // - Stream yield
                      60000n + // --- FPD yield
                      90600n, // ---- FD1 yield
                    (RATE_FACTOR / 100n) * 1n,
                    86400n
                  ) // ---------------------------------------------------------- FD2 T3: 41506
              ],
              tieredLastDayPartialYield: [
                // LPD Total: 23105
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n * 6n), // - LPD T1: 7500
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n * 6n), // - LPD T2: 5000
                simpleYield(
                  3000000n + // - Initial balance
                    1000000n + // - Stream yield
                    60000n + // --- FPD yield
                    90600n + // --- FD1 yield
                    91506n, // ---- FD2 yield
                  (RATE_FACTOR / 100n) * 1n,
                  3600n * 6n
                ) // ------------------------------------------------------------- LPD T3: 10605
              ]
            }
          ]
        }
      },
      {
        description: "Two yield rates",
        state: {
          lastUpdateTimestamp: INITIAL_DAY_INDEX * DAY + HOUR * 6n,
          lastUpdateBalance: 3000000n,
          streamYield: 1000000n,
          accruedYield: 2000000n,
          flags: 0n
        },
        rates: [
          {
            tiers: [
              { rate: RATE_FACTOR / 1000n, cap: 0n } // - 0.1% rate, no cap
            ],
            effectiveDay: 0n
          },
          {
            tiers: [
              { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
            ],
            effectiveDay: INITIAL_DAY_INDEX
          },
          {
            tiers: [
              { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
            ],
            effectiveDay: INITIAL_DAY_INDEX + 2n
          },
          {
            tiers: [
              { rate: RATE_FACTOR / 1000n, cap: 0n } // - 0.1% rate, no cap
            ],
            effectiveDay: INITIAL_DAY_INDEX + 1000n
          }
        ],
        currentTimestamp: INITIAL_DAY_INDEX * DAY + DAY * 3n + HOUR * 6n,
        expected: {
          fromTimestamp: INITIAL_DAY_INDEX * DAY + HOUR * 6n,
          toTimestamp: INITIAL_DAY_INDEX * DAY + DAY * 3n + HOUR * 6n,
          balance: 3000000n,
          streamYieldBefore: 1000000n,
          accruedYieldBefore: 2000000n,
          accruedYieldAfter:
            2000000n + // -------------- Initial accrued yield
            1000000n + // -------------- Initial stream yield
            60000n + // ---------------- FPD yield
            90600n + // ---------------- FD1 yield
            91506n, // ----------------- FD2 yield
          streamYieldAfter: 23105n, // - LPD yield
          rates: [
            {
              tiers: [
                { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
                { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
                { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
              ],
              effectiveDay: INITIAL_DAY_INDEX
            },
            {
              tiers: [
                { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
                { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
                { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
              ],
              effectiveDay: INITIAL_DAY_INDEX + 2n
            }
          ],
          results: [
            {
              firstDayPartialYield:
                // FPD Total: 60000
                1000000n + // - Stream yield
                22500n + // --- T1: 3% on 1000000 for 18 hours (Initial balance)
                15000n + // --- T2: 2% on 2000000 for 18 hours (Initial balance)
                22500n, // ---- T3: 1% on 3000000 for 18 hours (Initial balance)
              fullDaysYield:
                // FD1 Total: 90600
                30000n + // - T1: 3% on 1000000 for 1 day (Initial balance)
                20000n + // - T2: 2% on 1000000 for 1 day (Initial balance)
                30000n + // - T3: 1% on 3000000 for 1 day (Initial balance)
                10000n + // - T3: 1% on 1000000 for 1 day (Stream yield)
                600n, // --- T3: 1% on 60000 for 1 day (FPD yield)
              lastDayPartialYield: 0n,
              tieredFirstDayPartialYield: [
                // FPD Total: 60000
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n * 18n), // - FPD T1: 22500
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n * 18n), // - FPD T2: 15000
                simpleYield(3000000n, (RATE_FACTOR / 100n) * 1n, 3600n * 18n) // -- FPD T3: 22500
              ],
              tieredFullDaysYield: [
                // FD1 Total: 30000 + 20000 + 40600 = 90600
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n), // - FD1 T1: 30000
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n), // - FD1 T2: 20000
                simpleYield(
                  3000000n + // - Initial balance
                    1000000n + // - Stream yield
                    60000n, // ---- FPD yield
                  (RATE_FACTOR / 100n) * 1n,
                  86400n
                ) // --------------------------------------------------------- FD1 T3: 40600
              ],
              tieredLastDayPartialYield: [0n, 0n, 0n]
            },
            {
              firstDayPartialYield: 0n,
              fullDaysYield:
                // FD2 Total: 91506
                30000n + // - T1: 3% on 1000000 for 1 day (Initial balance)
                20000n + // - T2: 2% on 1000000 for 1 day (Initial balance)
                30000n + // - T3: 1% on 3000000 for 1 day (Initial balance)
                10000n + // - T3: 1% on 1000000 for 1 day (Stream yield)
                600n + // --- T3: 1% on 60000 for 1 day (FPD yield)
                906n, // ---- T3: 1% on 90600 for 1 day (FD1 yield)
              lastDayPartialYield:
                // LPD Total: 23105
                7500n + // - T1: 3% on 1000000 for 6 hours (Initial balance)
                5000n + // - T2: 2% on 1000000 for 6 hours (Initial balance)
                7500n + // - T3: 1% on 3000000 for 6 hours (Initial balance)
                2500n + // - T3: 1% on 1000000 for 6 hours (Stream yield)
                605n, // --- T3: 1% on 242106 for 6 hours (Accrued yield)
              tieredFirstDayPartialYield: [0n, 0n, 0n],
              tieredFullDaysYield: [
                // FD2 Total: 30000 + 20000 + 41506 = 91506
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n), // - FD2 T1: 30000
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n), // - FD2 T2: 20000
                simpleYield(
                  3000000n + // - Initial balance
                    1000000n + // - Stream yield
                    60000n + // --- FPD yield
                    90600n, // ---- FD1 yield
                  (RATE_FACTOR / 100n) * 1n,
                  86400n
                ) // --------------------------------------------------------- FD2 T3: 41506
              ],
              tieredLastDayPartialYield: [
                // LPD Total: 23105
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n * 6n), // - LPD T1: 7500
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n * 6n), // - LPD T2: 5000
                simpleYield(
                  3000000n + // - Initial balance
                    1000000n + // - Stream yield
                    60000n + // --- FPD yield
                    90600n + // --- FD1 yield
                    91506n, // ---- FD2 yield
                  (RATE_FACTOR / 100n) * 1n,
                  3600n * 6n
                ) // ------------------------------------------------------------- LPD T3: 10605
              ]
            }
          ]
        }
      },
      {
        description: "Three yield rates",
        state: {
          lastUpdateTimestamp: INITIAL_DAY_INDEX * DAY + HOUR * 6n,
          lastUpdateBalance: 3000000n,
          streamYield: 1000000n,
          accruedYield: 2000000n,
          flags: 0n
        },
        rates: [
          {
            tiers: [
              { rate: RATE_FACTOR / 1000n, cap: 0n } // - 0.1% rate, no cap
            ],
            effectiveDay: 0n
          },
          {
            tiers: [
              { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
            ],
            effectiveDay: INITIAL_DAY_INDEX
          },
          {
            tiers: [
              { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
            ],
            effectiveDay: INITIAL_DAY_INDEX + 2n
          },
          {
            tiers: [
              { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
            ],
            effectiveDay: INITIAL_DAY_INDEX + 3n
          },
          {
            tiers: [
              { rate: RATE_FACTOR / 1000n, cap: 0n } // - 0.1% rate, no cap
            ],
            effectiveDay: INITIAL_DAY_INDEX + 1000n
          }
        ],
        currentTimestamp: INITIAL_DAY_INDEX * DAY + DAY * 3n + HOUR * 6n,
        expected: {
          fromTimestamp: INITIAL_DAY_INDEX * DAY + HOUR * 6n,
          toTimestamp: INITIAL_DAY_INDEX * DAY + DAY * 3n + HOUR * 6n,
          balance: 3000000n,
          streamYieldBefore: 1000000n,
          accruedYieldBefore: 2000000n,
          accruedYieldAfter:
            2000000n + // -------------- Initial accrued yield
            1000000n + // -------------- Initial stream yield
            60000n + // ---------------- FPD yield
            90600n + // ---------------- FD1 yield
            91506n, // ----------------- FD2 yield
          streamYieldAfter: 23105n, // - LPD yield
          rates: [
            {
              tiers: [
                { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
                { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
                { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
              ],
              effectiveDay: INITIAL_DAY_INDEX
            },
            {
              tiers: [
                { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
                { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
                { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
              ],
              effectiveDay: INITIAL_DAY_INDEX + 2n
            },
            {
              tiers: [
                { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
                { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
                { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
              ],
              effectiveDay: INITIAL_DAY_INDEX + 3n
            }
          ],
          results: [
            {
              firstDayPartialYield:
                // FPD Total: 60000
                1000000n + // - Stream yield
                22500n + // --- T1: 3% on 1000000 for 18 hours (Initial balance)
                15000n + // --- T2: 2% on 2000000 for 18 hours (Initial balance)
                22500n, // ---- T3: 1% on 3000000 for 18 hours (Initial balance)
              fullDaysYield:
                // FD1 Total: 90600
                30000n + // - T1: 3% on 1000000 for 1 day (Initial balance)
                20000n + // - T2: 2% on 1000000 for 1 day (Initial balance)
                30000n + // - T3: 1% on 3000000 for 1 day (Initial balance)
                10000n + // - T3: 1% on 1000000 for 1 day (Stream yield)
                600n, // ---- T3: 1% on 60000 for 1 day (FPD yield)
              lastDayPartialYield: 0n,
              tieredFirstDayPartialYield: [
                // FPD Total: 60000
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n * 18n), // - FPD T1: 22500
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n * 18n), // - FPD T2: 15000
                simpleYield(3000000n, (RATE_FACTOR / 100n) * 1n, 3600n * 18n) // -- FPD T3: 22500
              ],
              tieredFullDaysYield: [
                // FD1 Total: 30000 + 20000 + 40600 = 90600
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n), // - FD1 T1: 30000
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n), // - FD1 T2: 20000
                simpleYield(
                  3000000n + // - Initial balance
                    1000000n + // - Stream yield
                    60000n, // ---- FPD yield
                  (RATE_FACTOR / 100n) * 1n,
                  86400n
                ) // ---------------------------------------------------------- FD1 T3: 40600
              ],
              tieredLastDayPartialYield: [0n, 0n, 0n]
            },
            {
              firstDayPartialYield: 0n,
              fullDaysYield:
                // FD2 Total: 91506
                30000n + // - T1: 3% on 1000000 for 1 day (Initial balance)
                20000n + // - T2: 2% on 1000000 for 1 day (Initial balance)
                30000n + // - T3: 1% on 3000000 for 1 day (Initial balance)
                10000n + // - T3: 1% on 1000000 for 1 day (Stream yield)
                600n + // --- T3: 1% on 60000 for 1 day (FPD yield)
                906n, // ---- T3: 1% on 90600 for 1 day (FD1 yield)
              lastDayPartialYield: 0n,
              tieredFirstDayPartialYield: [0n, 0n, 0n],
              tieredFullDaysYield: [
                // FD2 Total: 30000 + 20000 + 41506 = 91506
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n), // - FD2 T1: 30000
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n), // - FD2 T2: 20000
                simpleYield(
                  3000000n + // - Initial balance
                    1000000n + // - Stream yield
                    60000n + // --- FPD yield
                    90600n, // ---- FD1 yield
                  (RATE_FACTOR / 100n) * 1n,
                  86400n
                ) // --------------------------------------------------------- FD2 T3: 41506
              ],
              tieredLastDayPartialYield: [0n, 0n, 0n]
            },
            {
              firstDayPartialYield: 0n,
              fullDaysYield: 0n,
              lastDayPartialYield:
                // LPD Total: 23105
                7500n + // - T1: 3% on 1000000 for 6 hours (Initial balance)
                5000n + // - T2: 2% on 1000000 for 6 hours (Initial balance)
                7500n + // - T3: 1% on 3000000 for 6 hours (Initial balance)
                2500n + // - T3: 1% on 1000000 for 6 hours (Stream yield)
                605n, // --- T3: 1% on 242106 for 6 hours (Accrued yield)
              tieredFirstDayPartialYield: [0n, 0n, 0n],
              tieredFullDaysYield: [0n, 0n, 0n],
              tieredLastDayPartialYield: [
                // LPD Total: 23105
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n * 6n), // - LPD T1: 7500
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n * 6n), // - LPD T2: 5000
                simpleYield(
                  3000000n + // - Initial balance
                    1000000n + // - Stream yield
                    60000n + // --- FPD yield
                    90600n + // --- FD1 yield
                    91506n, // ---- FD2 yield
                  (RATE_FACTOR / 100n) * 1n,
                  3600n * 6n
                ) // ------------------------------------------------------------- LPD T3: 10605
              ]
            }
          ]
        }
      }
    ];

    testCases.forEach((testCase, index) => {
      it(`Test case ${index + 1}: ${testCase.description}`, async function () {
        // Add yield rates to contract
        for (let i = 0; i < testCase.rates.length; i++) {
          await yieldStreamerTestable.addYieldRate(
            0,
            testCase.rates[i].effectiveDay,
            testCase.rates[i].tiers.map(tier => tier.rate),
            testCase.rates[i].tiers.map(tier => tier.cap)
          );
        }

        const result = await yieldStreamerTestable.getAccruePreview(
          testCase.state,
          testCase.rates,
          testCase.currentTimestamp
        );

        // Convert result to comparable format
        const normalizedResult: AccruePreview = {
          fromTimestamp: result.fromTimestamp,
          toTimestamp: result.toTimestamp,
          balance: result.balance,
          streamYieldBefore: result.streamYieldBefore,
          accruedYieldBefore: result.accruedYieldBefore,
          streamYieldAfter: result.streamYieldAfter,
          accruedYieldAfter: result.accruedYieldAfter,
          rates: result.rates.map((r: YieldRate) => ({
            tiers: r.tiers.map((t: RateTier) => ({
              rate: t.rate,
              cap: t.cap
            })),
            effectiveDay: r.effectiveDay
          })),
          results: result.results.map((r: YieldResult) => ({
            firstDayPartialYield: r.firstDayPartialYield,
            fullDaysYield: r.fullDaysYield,
            lastDayPartialYield: r.lastDayPartialYield,
            tieredFirstDayPartialYield: r.tieredFirstDayPartialYield.map((n: bigint) => n),
            tieredFullDaysYield: r.tieredFullDaysYield.map((n: bigint) => n),
            tieredLastDayPartialYield: r.tieredLastDayPartialYield.map((n: bigint) => n)
          }))
        };

        // Compare each field
        expect(normalizedResult.fromTimestamp).to.equal(testCase.expected.fromTimestamp);
        expect(normalizedResult.toTimestamp).to.equal(testCase.expected.toTimestamp);
        expect(normalizedResult.balance).to.equal(testCase.expected.balance);
        expect(normalizedResult.streamYieldBefore).to.equal(testCase.expected.streamYieldBefore);
        expect(normalizedResult.accruedYieldBefore).to.equal(testCase.expected.accruedYieldBefore);
        expect(normalizedResult.streamYieldAfter).to.equal(testCase.expected.streamYieldAfter);
        expect(normalizedResult.accruedYieldAfter).to.equal(testCase.expected.accruedYieldAfter);
        expect(normalizedResult.rates).to.deep.equal(testCase.expected.rates);
        // expect(normalizedResult.results).to.deep.equal(testCase.expected.results);
      });
    });
  });

  describe("Function 'calculateYield()'", function () {
    let yieldStreamerTestable: Contract;

    beforeEach(async function () {
      const contracts = await setUpFixture(deployContracts);
      yieldStreamerTestable = contracts.yieldStreamerTestable;
    });

    interface CalculateYieldTestCase {
      description: string;
      params: {
        fromTimestamp: bigint;
        toTimestamp: bigint;
        rateStartIndex: bigint;
        rateEndIndex: bigint;
        initialBalance: bigint;
        initialStreamYield: bigint;
        initialAccruedYield: bigint;
      };
      rates: YieldRate[];
      expected: YieldResult[];
    }

    const testCases: CalculateYieldTestCase[] = [
      {
        description: "One yield rate",
        params: {
          fromTimestamp: INITIAL_DAY_INDEX * DAY + HOUR * 6n,
          toTimestamp: INITIAL_DAY_INDEX * DAY + DAY * 3n + HOUR * 6n,
          rateStartIndex: 1n,
          rateEndIndex: 1n,
          initialBalance: 3000000n,
          initialStreamYield: 1000000n,
          initialAccruedYield: 2000000n
        },
        rates: [
          {
            tiers: [
              { rate: RATE_FACTOR / 1000n, cap: 0n } // - 0.1% rate, no cap
            ],
            effectiveDay: 0n
          },
          {
            tiers: [
              { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
            ],
            effectiveDay: INITIAL_DAY_INDEX
          }
        ],
        expected: [
          {
            firstDayPartialYield:
              // FPD Total: 60000
              1000000n + // - Stream yield
              22500n + // --- T1: 3% on 1000000 for 18 hours (Initial balance)
              15000n + // --- T2: 2% on 2000000 for 18 hours (Initial balance)
              22500n, // ---- T3: 1% on 3000000 for 18 hours (Initial balance)
            fullDaysYield:
              // FD1 Total: 90600
              30000n + // - T1: 3% on 1000000 for 1 day (Initial balance)
              20000n + // - T2: 2% on 1000000 for 1 day (Initial balance)
              30000n + // - T3: 1% on 3000000 for 1 day (Initial balance)
              10000n + // - T3: 1% on 1000000 for 1 day (Stream yield)
              600n + // --- T3: 1% on 60000 for 1 day (FPD yield)
              // ------
              // FD2 Total: 91506
              30000n + // - T1: 3% on 1000000 for 1 day (Initial balance)
              20000n + // - T2: 2% on 1000000 for 1 day (Initial balance)
              30000n + // - T3: 1% on 3000000 for 1 day (Initial balance)
              10000n + // - T3: 1% on 1000000 for 1 day (Stream yield)
              600n + // --- T3: 1% on 60000 for 1 day (FPD yield)
              906n, // ---- T3: 1% on 90600 for 1 day (FD1 yield)
            lastDayPartialYield:
              // LPD Total: 23105
              7500n + // - T1: 3% on 1000000 for 6 hours (Initial balance)
              5000n + // - T2: 2% on 1000000 for 6 hours (Initial balance)
              7500n + // - T3: 1% on 3000000 for 6 hours (Initial balance)
              2500n + // - T3: 1% on 1000000 for 6 hours (Stream yield)
              605n, // --- T3: 1% on 242106 for 6 hours (Accrued yield)
            tieredFirstDayPartialYield: [
              // FPD Total: 60000
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n * 18n), // - FPD T1: 22500
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n * 18n), // - FPD T2: 15000
              simpleYield(3000000n, (RATE_FACTOR / 100n) * 1n, 3600n * 18n) // -- FPD T3: 22500
            ],
            tieredFullDaysYield: [
              // FD1 + FD2 Total: 182106
              // FD1 Total: 30000 + 20000 + 40600 = 90600
              // FD2 Total: 30000 + 20000 + 41506 = 91506
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n) + // - FD1 T1: 30000
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n), // -- FD2 T1: 30000
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n) + // - FD1 T2: 20000
                simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n), // -- FD2 T2: 20000
              simpleYield(
                3000000n + // - Initial balance
                  1000000n + // - Stream yield
                  60000n, // ---- FPD yield
                (RATE_FACTOR / 100n) * 1n,
                86400n
              ) + // -------------------------------------------------------- FD1 T3: 40600
                simpleYield(
                  3000000n + // - Initial balance
                    1000000n + // - Stream yield
                    60000n + // --- FPD yield
                    90600n, // ---- FD1 yield
                  (RATE_FACTOR / 100n) * 1n,
                  86400n
                ) // ---------------------------------------------------------- FD2 T3: 41506
            ],
            tieredLastDayPartialYield: [
              // LPD Total: 23105
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n * 6n), // - LPD T1: 7500
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n * 6n), // - LPD T2: 5000
              simpleYield(
                3000000n + // - Initial balance
                  1000000n + // - Stream yield
                  60000n + // --- FPD yield
                  90600n + // --- FD1 yield
                  91506n, // ---- FD2 yield
                (RATE_FACTOR / 100n) * 1n,
                3600n * 6n
              ) // ------------------------------------------------------------- LPD T3: 10605
            ]
          }
        ]
      },
      {
        description: "Two yield rates",
        params: {
          fromTimestamp: INITIAL_DAY_INDEX * DAY + HOUR * 6n,
          toTimestamp: INITIAL_DAY_INDEX * DAY + DAY * 3n + HOUR * 6n,
          rateStartIndex: 1n,
          rateEndIndex: 2n,
          initialBalance: 3000000n,
          initialStreamYield: 1000000n,
          initialAccruedYield: 2000000n
        },
        rates: [
          {
            tiers: [
              { rate: RATE_FACTOR / 1000n, cap: 0n } // - 0.1% rate, no cap
            ],
            effectiveDay: 0n
          },
          {
            tiers: [
              { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
            ],
            effectiveDay: INITIAL_DAY_INDEX
          },
          {
            tiers: [
              { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
            ],
            effectiveDay: INITIAL_DAY_INDEX + 2n
          }
        ],
        expected: [
          {
            firstDayPartialYield:
              // FPD Total: 60000
              1000000n + // - Stream yield
              22500n + // --- T1: 3% on 1000000 for 18 hours (Initial balance)
              15000n + // --- T2: 2% on 2000000 for 18 hours (Initial balance)
              22500n, // ---- T3: 1% on 3000000 for 18 hours (Initial balance)
            fullDaysYield:
              // FD1 Total: 90600
              30000n + // - T1: 3% on 1000000 for 1 day (Initial balance)
              20000n + // - T2: 2% on 1000000 for 1 day (Initial balance)
              30000n + // - T3: 1% on 3000000 for 1 day (Initial balance)
              10000n + // - T3: 1% on 1000000 for 1 day (Stream yield)
              600n, // --- T3: 1% on 60000 for 1 day (FPD yield)
            lastDayPartialYield: 0n,
            tieredFirstDayPartialYield: [
              // FPD Total: 60000
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n * 18n), // - FPD T1: 22500
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n * 18n), // - FPD T2: 15000
              simpleYield(3000000n, (RATE_FACTOR / 100n) * 1n, 3600n * 18n) // -- FPD T3: 22500
            ],
            tieredFullDaysYield: [
              // FD1 Total: 30000 + 20000 + 40600 = 90600
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n), // - FD1 T1: 30000
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n), // - FD1 T2: 20000
              simpleYield(
                3000000n + // - Initial balance
                  1000000n + // - Stream yield
                  60000n, // ---- FPD yield
                (RATE_FACTOR / 100n) * 1n,
                86400n
              ) // --------------------------------------------------------- FD1 T3: 40600
            ],
            tieredLastDayPartialYield: [0n, 0n, 0n]
          },
          {
            firstDayPartialYield: 0n,
            fullDaysYield:
              // FD2 Total: 91506
              30000n + // - T1: 3% on 1000000 for 1 day (Initial balance)
              20000n + // - T2: 2% on 1000000 for 1 day (Initial balance)
              30000n + // - T3: 1% on 3000000 for 1 day (Initial balance)
              10000n + // - T3: 1% on 1000000 for 1 day (Stream yield)
              600n + // --- T3: 1% on 60000 for 1 day (FPD yield)
              906n, // ---- T3: 1% on 90600 for 1 day (FD1 yield)
            lastDayPartialYield:
              // LPD Total: 23105
              7500n + // - T1: 3% on 1000000 for 6 hours (Initial balance)
              5000n + // - T2: 2% on 1000000 for 6 hours (Initial balance)
              7500n + // - T3: 1% on 3000000 for 6 hours (Initial balance)
              2500n + // - T3: 1% on 1000000 for 6 hours (Stream yield)
              605n, // --- T3: 1% on 242106 for 6 hours (Accrued yield)
            tieredFirstDayPartialYield: [0n, 0n, 0n],
            tieredFullDaysYield: [
              // FD2 Total: 30000 + 20000 + 41506 = 91506
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n), // - FD2 T1: 30000
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n), // - FD2 T2: 20000
              simpleYield(
                3000000n + // - Initial balance
                  1000000n + // - Stream yield
                  60000n + // --- FPD yield
                  90600n, // ---- FD1 yield
                (RATE_FACTOR / 100n) * 1n,
                86400n
              ) // --------------------------------------------------------- FD2 T3: 41506
            ],
            tieredLastDayPartialYield: [
              // LPD Total: 23105
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n * 6n), // - LPD T1: 7500
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n * 6n), // - LPD T2: 5000
              simpleYield(
                3000000n + // - Initial balance
                  1000000n + // - Stream yield
                  60000n + // --- FPD yield
                  90600n + // --- FD1 yield
                  91506n, // ---- FD2 yield
                (RATE_FACTOR / 100n) * 1n,
                3600n * 6n
              ) // ------------------------------------------------------------- LPD T3: 10605
            ]
          }
        ]
      },
      {
        description: "Three yield rate",
        params: {
          fromTimestamp: INITIAL_DAY_INDEX * DAY + HOUR * 6n,
          toTimestamp: INITIAL_DAY_INDEX * DAY + DAY * 3n + HOUR * 6n,
          rateStartIndex: 1n,
          rateEndIndex: 3n,
          initialBalance: 3000000n,
          initialStreamYield: 1000000n,
          initialAccruedYield: 2000000n
        },
        rates: [
          {
            tiers: [
              { rate: RATE_FACTOR / 1000n, cap: 0n } // - 0.1% rate, no cap
            ],
            effectiveDay: 0n
          },
          {
            tiers: [
              { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
            ],
            effectiveDay: INITIAL_DAY_INDEX
          },
          {
            tiers: [
              { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
            ],
            effectiveDay: INITIAL_DAY_INDEX + 2n
          },
          {
            tiers: [
              { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
              { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
            ],
            effectiveDay: INITIAL_DAY_INDEX + 3n
          }
        ],
        expected: [
          {
            firstDayPartialYield:
              // FPD Total: 60000
              1000000n + // - Stream yield
              22500n + // --- T1: 3% on 1000000 for 18 hours (Initial balance)
              15000n + // --- T2: 2% on 2000000 for 18 hours (Initial balance)
              22500n, // ---- T3: 1% on 3000000 for 18 hours (Initial balance)
            fullDaysYield:
              // FD1 Total: 90600
              30000n + // - T1: 3% on 1000000 for 1 day (Initial balance)
              20000n + // - T2: 2% on 1000000 for 1 day (Initial balance)
              30000n + // - T3: 1% on 3000000 for 1 day (Initial balance)
              10000n + // - T3: 1% on 1000000 for 1 day (Stream yield)
              600n, // ---- T3: 1% on 60000 for 1 day (FPD yield)
            lastDayPartialYield: 0n,
            tieredFirstDayPartialYield: [
              // FPD Total: 60000
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n * 18n), // - FPD T1: 22500
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n * 18n), // - FPD T2: 15000
              simpleYield(3000000n, (RATE_FACTOR / 100n) * 1n, 3600n * 18n) // -- FPD T3: 22500
            ],
            tieredFullDaysYield: [
              // FD1 Total: 30000 + 20000 + 40600 = 90600
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n), // - FD1 T1: 30000
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n), // - FD1 T2: 20000
              simpleYield(
                3000000n + // - Initial balance
                  1000000n + // - Stream yield
                  60000n, // ---- FPD yield
                (RATE_FACTOR / 100n) * 1n,
                86400n
              ) // ---------------------------------------------------------- FD1 T3: 40600
            ],
            tieredLastDayPartialYield: [0n, 0n, 0n]
          },
          {
            firstDayPartialYield: 0n,
            fullDaysYield:
              // FD2 Total: 91506
              30000n + // - T1: 3% on 1000000 for 1 day (Initial balance)
              20000n + // - T2: 2% on 1000000 for 1 day (Initial balance)
              30000n + // - T3: 1% on 3000000 for 1 day (Initial balance)
              10000n + // - T3: 1% on 1000000 for 1 day (Stream yield)
              600n + // --- T3: 1% on 60000 for 1 day (FPD yield)
              906n, // ---- T3: 1% on 90600 for 1 day (FD1 yield)
            lastDayPartialYield: 0n,
            tieredFirstDayPartialYield: [0n, 0n, 0n],
            tieredFullDaysYield: [
              // FD2 Total: 30000 + 20000 + 41506 = 91506
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n), // - FD2 T1: 30000
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n), // - FD2 T2: 20000
              simpleYield(
                3000000n + // - Initial balance
                  1000000n + // - Stream yield
                  60000n + // --- FPD yield
                  90600n, // ---- FD1 yield
                (RATE_FACTOR / 100n) * 1n,
                86400n
              ) // --------------------------------------------------------- FD2 T3: 41506
            ],
            tieredLastDayPartialYield: [0n, 0n, 0n]
          },
          {
            firstDayPartialYield: 0n,
            fullDaysYield: 0n,
            lastDayPartialYield:
              // LPD Total: 23105
              7500n + // - T1: 3% on 1000000 for 6 hours (Initial balance)
              5000n + // - T2: 2% on 1000000 for 6 hours (Initial balance)
              7500n + // - T3: 1% on 3000000 for 6 hours (Initial balance)
              2500n + // - T3: 1% on 1000000 for 6 hours (Stream yield)
              605n, // --- T3: 1% on 242106 for 6 hours (Accrued yield)
            tieredFirstDayPartialYield: [0n, 0n, 0n],
            tieredFullDaysYield: [0n, 0n, 0n],
            tieredLastDayPartialYield: [
              // LPD Total: 23105
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n * 6n), // - LPD T1: 7500
              simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n * 6n), // - LPD T2: 5000
              simpleYield(
                3000000n + // - Initial balance
                  1000000n + // - Stream yield
                  60000n + // --- FPD yield
                  90600n + // --- FD1 yield
                  91506n, // ---- FD2 yield
                (RATE_FACTOR / 100n) * 1n,
                3600n * 6n
              ) // ------------------------------------------------------------- LPD T3: 10605
            ]
          }
        ]
      }
    ];

    testCases.forEach((testCase, index) => {
      it(`Test case ${index + 1}: ${testCase.description}`, async function () {
        // Add yield rates to contract
        testCase.rates.forEach(async rate => {
          await yieldStreamerTestable.addYieldRate(
            0,
            rate.effectiveDay,
            rate.tiers.map(tier => tier.rate),
            rate.tiers.map(tier => tier.cap)
          );
        });

        const result = await yieldStreamerTestable.calculateYield(testCase.params, testCase.rates);

        // Convert result to comparable format
        const normalizedResult: YieldResult[] = result.map((r: any) => ({
          firstDayPartialYield: r.firstDayPartialYield,
          fullDaysYield: r.fullDaysYield,
          lastDayPartialYield: r.lastDayPartialYield,
          tieredFirstDayPartialYield: r.tieredFirstDayPartialYield.map((n: bigint) => n),
          tieredFullDaysYield: r.tieredFullDaysYield.map((n: bigint) => n),
          tieredLastDayPartialYield: r.tieredLastDayPartialYield.map((n: bigint) => n)
        }));

        // Compare each result
        expect(normalizedResult).to.deep.equal(testCase.expected);
      });
    });
  });

  describe("Function 'compoundYield()'", function () {
    let yieldStreamerTestable: Contract;

    beforeEach(async function () {
      const contracts = await setUpFixture(deployContracts);
      yieldStreamerTestable = contracts.yieldStreamerTestable;
    });

    interface CompoundYieldTestCase {
      description: string;
      params: {
        fromTimestamp: bigint;
        toTimestamp: bigint;
        tiers: RateTier[];
        balance: bigint;
        streamYield: bigint;
      };
      expected: {
        firstDayPartialYield: bigint;
        fullDaysYield: bigint;
        lastDayPartialYield: bigint;
        tieredFirstDayPartialYield: bigint[];
        tieredFullDaysYield: bigint[];
        tieredLastDayPartialYield: bigint[];
      };
      shouldRevert?: boolean;
      revertMessage?: string;
    }

    const testCases: CompoundYieldTestCase[] = [
      {
        description: "Single partial day: D1:00:00:00 - D1:01:00:00",
        params: {
          fromTimestamp: 86400n,
          toTimestamp: 86400n + 3600n,
          tiers: [
            { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
            { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
            { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
          ],
          balance: 5000000n,
          streamYield: 1000000n
        },
        expected: {
          firstDayPartialYield: 1000000n,
          fullDaysYield: 0n,
          lastDayPartialYield: 1250n + 833n + 1666n,
          tieredFirstDayPartialYield: [0n, 0n, 0n],
          tieredFullDaysYield: [0n, 0n, 0n],
          tieredLastDayPartialYield: [
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n), // ----------- 1250
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n), // ----------- 833
            simpleYield(3000000n + 1000000n, (RATE_FACTOR / 100n) * 1n, 3600n) // - 1666
          ]
        }
      },
      {
        description: "Single partial day: D1:01:00:00 - D1:23:00:00",
        params: {
          fromTimestamp: 86400n + 3600n,
          toTimestamp: 86400n + 86400n - 3600n,
          tiers: [
            { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
            { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
            { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
          ],
          balance: 5000000n,
          streamYield: 1000000n
        },
        expected: {
          firstDayPartialYield: 0n,
          fullDaysYield: 0n,
          lastDayPartialYield: 1000000n + 27500n + 18333n + 27500n,
          tieredFirstDayPartialYield: [0n, 0n, 0n],
          tieredFullDaysYield: [0n, 0n, 0n],
          tieredLastDayPartialYield: [
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n * 22n), // - 27500
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n * 22n), // - 18333
            simpleYield(3000000n, (RATE_FACTOR / 100n) * 1n, 3600n * 22n) // -- 27500
          ]
        }
      },
      {
        description: "Single partial day: D1:23:00:00 - D2:00:00:00",
        params: {
          fromTimestamp: 86400n + 86400n - 3600n,
          toTimestamp: 86400n + 86400n,
          tiers: [
            { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
            { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
            { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
          ],
          balance: 5000000n,
          streamYield: 1000000n
        },
        expected: {
          firstDayPartialYield: 0n,
          fullDaysYield: 0n,
          lastDayPartialYield: 1000000n + 1250n + 833n + 1250n,
          tieredFirstDayPartialYield: [0n, 0n, 0n],
          tieredFullDaysYield: [0n, 0n, 0n],
          tieredLastDayPartialYield: [
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n), // - 1250
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n), // - 833
            simpleYield(3000000n, (RATE_FACTOR / 100n) * 1n, 3600n) // -- 1250
          ]
        }
      },
      {
        description: "Single full day: D1:00:00:00 - D2:00:00:00",
        params: {
          fromTimestamp: 86400n,
          toTimestamp: 86400n + 86400n,
          tiers: [
            { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
            { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
            { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
          ],
          balance: 5000000n,
          streamYield: 1000000n
        },
        expected: {
          firstDayPartialYield: 1000000n,
          fullDaysYield: 30000n + 20000n + 40000n,
          lastDayPartialYield: 0n,
          tieredFirstDayPartialYield: [0n, 0n, 0n],
          tieredFullDaysYield: [
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n), // ----------- 30000
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n), // ----------- 20000
            simpleYield(3000000n + 1000000n, (RATE_FACTOR / 100n) * 1n, 86400n) // - 30000 + 10000 = 40000
          ],
          tieredLastDayPartialYield: [0n, 0n, 0n]
        }
      },
      {
        description: "Two full days: D1:00:00:00 - D3:00:00:00",
        params: {
          fromTimestamp: 86400n,
          toTimestamp: 86400n + 86400n * 2n,
          tiers: [
            { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
            { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
            { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
          ],
          balance: 5000000n,
          streamYield: 1000000n
        },
        expected: {
          firstDayPartialYield: 1000000n,
          fullDaysYield: 30000n + 20000n + 30000n + 20000n + 40000n + 40900n,
          lastDayPartialYield: 0n,
          tieredFirstDayPartialYield: [0n, 0n, 0n],
          tieredFullDaysYield: [
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n) + // ------------------- T1 D1: 30000
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n), // -------------------- T1 D2: 30000
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n) + // ------------------- T2 D1: 20000
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n), // -------------------- T2 D2: 20000
            simpleYield(3000000n + 1000000n, (RATE_FACTOR / 100n) * 1n, 86400n) + // -------- T3 D1: 30000 + 10000 = 40000
            simpleYield(3000000n + 1000000n + 90000n, (RATE_FACTOR / 100n) * 1n, 86400n) // - T3 D2: 30000 + 10000 + 900 = 40900
          ],
          tieredLastDayPartialYield: [0n, 0n, 0n]
        }
      },
      {
        description: "Two full days ANDFirst partial day: D1:06:00:00 - D4:00:00:00",
        params: {
          fromTimestamp: 86400n + 3600n * 6n,
          toTimestamp: 86400n + 86400n * 3n,
          tiers: [
            { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
            { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
            { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
          ],
          balance: 5000000n,
          streamYield: 1000000n
        },
        expected: {
          firstDayPartialYield:
            // PD0
            1000000n + // - stream yield
            22500n + // --- T1: 3% on 1000000 for 18 hours
            15000n + // --- T2: 2% on 2000000 for 18 hours
            22500n, // ---- T3: 1% on 3000000 for 18 hours
          // PD0 Total: 60000
          fullDaysYield:
            // FD1
            30000n + // - T1: 3% on 1000000 (balance) for 1 day
            20000n + // - T2: 2% on 1000000 (balance) for 1 day
            30000n + // - T3: 1% on 3000000 (balance) for 1 day
            10000n + // - T3: 1% on 1000000 (stream yield) for 1 day
            600n + // --- T3: 1% on 60000 (first day partial yield) for 1 day
            // FD1 Total: 90600
            // ------
            // FD2
            30000n + // - T1: 3% on 1000000 (balance) for 1 day
            20000n + // - T2: 2% on 1000000 (balance) for 1 day
            30000n + // - T3: 1% on 3000000 (balance) for 1 day
            10000n + // - T3: 1% on 1000000 (stream yield) for 1 day
            600n + // --- T3: 1% on 60000 (first day partial yield) for 1 day
            906n, // ---- T3: 1% on 90600 (FD1 yield) for 1 day
          // FD2 Total: 91506
          lastDayPartialYield: 0n,
          tieredFirstDayPartialYield: [
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n * 18n), // - PD0 T1: 22500
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n * 18n), // - PD0 T2: 15000
            simpleYield(3000000n, (RATE_FACTOR / 100n) * 1n, 3600n * 18n) // -- PD0 T3: 22500
          ],
          tieredFullDaysYield: [
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n) + // ---------------------------- FD1 T1: 30000
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n), // ----------------------------- FD2 T1: 30000
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n) + // ---------------------------- FD1 T2: 20000
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n), // ----------------------------- FD2 T2: 20000
            simpleYield(3000000n + 1000000n + 60000n, (RATE_FACTOR / 100n) * 1n, 86400n) + // -------- FD1 T3: 40400
            simpleYield(3000000n + 1000000n + 60000n + 90600n, (RATE_FACTOR / 100n) * 1n, 86400n) // - FD2 T3: 40900
          ],
          tieredLastDayPartialYield: [0n, 0n, 0n]
        }
      },
      {
        description: "Two full days AND Last partial day: D1:00:00:00 - D4:06:00:00",
        params: {
          fromTimestamp: 86400n,
          toTimestamp: 86400n + 86400n * 2n + 3600n * 6n,
          tiers: [
            { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
            { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
            { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
          ],
          balance: 5000000n,
          streamYield: 1000000n
        },
        expected: {
          firstDayPartialYield:
            // PD0
            1000000n, // - stream yield
          fullDaysYield:
            // FD1 Total: 90000
            30000n + // - T1: 3% on 1000000 (balance) for 1 day
            20000n + // - T2: 2% on 1000000 (balance) for 1 day
            30000n + // - T3: 1% on 3000000 (balance) for 1 day
            10000n + // - T3: 1% on 1000000 (stream yield) for 1 day
            // ------
            // FD2 Total: 91506
            30000n + // - T1: 3% on 1000000 (balance) for 1 day
            20000n + // - T2: 2% on 1000000 (balance) for 1 day
            30000n + // - T3: 1% on 3000000 (balance) for 1 day
            10000n + // - T3: 1% on 1000000 (stream yield) for 1 day
            900n, // ---- T3: 1% on 90000 (FD1 yield) for 1 day
          lastDayPartialYield: 22952n,
          tieredFirstDayPartialYield: [0n, 0n, 0n],
          tieredFullDaysYield: [
            // FD1 + FD2 Total: 180900
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n) + // ------------------- FD1 T1: 30000
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n), // -------------------- FD2 T1: 30000
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n) + // ------------------- FD1 T2: 20000
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n), // -------------------- FD2 T2: 20000
            simpleYield(3000000n + 1000000n, (RATE_FACTOR / 100n) * 1n, 86400n) + // -------- FD1 T3: 40000
            simpleYield(3000000n + 1000000n + 90000n, (RATE_FACTOR / 100n) * 1n, 86400n) // - FD2 T3: 40900
          ],
          tieredLastDayPartialYield: [
            // LDY Total: 22952
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n * 6n), // -- LDY T1: 7500
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n * 6n), // -- LDY T2: 5000
            simpleYield(3000000n, (RATE_FACTOR / 100n) * 1n, 3600n * 6n) + // - LDY T3: 7500
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 1n, 3600n * 6n) + // - LDY T3: 2500
            simpleYield(180900n, (RATE_FACTOR / 100n) * 1n, 3600n * 6n) // ---- LDY T3: 452
          ]
        }
      },
      {
        description: "Two full days AND First partial day AND Last partial day: D1:06:00:00 - D4:06:00:00",
        params: {
          fromTimestamp: 86400n + 3600n * 6n,
          toTimestamp: 86400n + 86400n * 3n + 3600n * 6n,
          tiers: [
            { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
            { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
            { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
          ],
          balance: 5000000n,
          streamYield: 1000000n
        },
        expected: {
          firstDayPartialYield:
            // FPD Total: 60000
            1000000n + // - Stream yield
            22500n + // --- T1: 3% on 1000000 for 18 hours (Initial balance)
            15000n + // --- T2: 2% on 2000000 for 18 hours (Initial balance)
            22500n, // ---- T3: 1% on 3000000 for 18 hours (Initial balance)
          fullDaysYield:
            // FD1 Total: 90600
            30000n + // - T1: 3% on 1000000 for 1 day (Initial balance)
            20000n + // - T2: 2% on 1000000 for 1 day (Initial balance)
            30000n + // - T3: 1% on 3000000 for 1 day (Initial balance)
            10000n + // - T3: 1% on 1000000 for 1 day (Stream yield)
            600n + // --- T3: 1% on 60000 for 1 day (FPD yield)
            // ------
            // FD2 Total: 91506
            30000n + // - T1: 3% on 1000000 for 1 day (Initial balance)
            20000n + // - T2: 2% on 1000000 for 1 day (Initial balance)
            30000n + // - T3: 1% on 3000000 for 1 day (Initial balance)
            10000n + // - T3: 1% on 1000000 for 1 day (Stream yield)
            600n + // --- T3: 1% on 60000 for 1 day (FPD yield)
            906n, // ---- T3: 1% on 90600 for 1 day (FD1 yield)
          lastDayPartialYield:
            // LPD Total: 23105
            7500n + // - T1: 3% on 1000000 for 6 hours (Initial balance)
            5000n + // - T2: 2% on 1000000 for 6 hours (Initial balance)
            7500n + // - T3: 1% on 3000000 for 6 hours (Initial balance)
            2500n + // - T3: 1% on 1000000 for 6 hours (Stream yield)
            605n, // --- T3: 1% on 242106 for 6 hours (Accrued yield)
          tieredFirstDayPartialYield: [
            // FPD Total: 60000
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n * 18n), // - FPD T1: 22500
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n * 18n), // - FPD T2: 15000
            simpleYield(3000000n, (RATE_FACTOR / 100n) * 1n, 3600n * 18n) // -- FPD T3: 22500
          ],
          tieredFullDaysYield: [
            // FD1 + FD2 Total: 182106
            // FD1 Total: 30000 + 20000 + 40600 = 90600
            // FD2 Total: 30000 + 20000 + 41506 = 91506
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n) + // - FD1 T1: 30000
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 86400n), // -- FD2 T1: 30000
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n) + // - FD1 T2: 20000
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 86400n), // -- FD2 T2: 20000
            simpleYield(
              3000000n + // - Initial balance
              1000000n + // - Stream yield
              60000n, // ---- FPD yield
              (RATE_FACTOR / 100n) * 1n,
              86400n
            ) + // -------------------------------------------------------- FD1 T3: 40600
            simpleYield(
              3000000n + // - Initial balance
              1000000n + // - Stream yield
              60000n + // --- FPD yield
              90600n, // ---- FD1 yield
              (RATE_FACTOR / 100n) * 1n,
              86400n
            ) // ---------------------------------------------------------- FD2 T3: 41506
          ],
          tieredLastDayPartialYield: [
            // LPD Total: 23105
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n * 6n), // - LPD T1: 7500
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n * 6n), // - LPD T2: 5000
            simpleYield(
              3000000n + // - Initial balance
              1000000n + // - Stream yield
              60000n + // --- FPD yield
              90600n + // --- FD1 yield
              91506n, // ---- FD2 yield
              (RATE_FACTOR / 100n) * 1n,
              3600n * 6n
            ) // ------------------------------------------------------------- LPD T3: 10605
          ]
        }
      },
      {
        description: "Two partial days: D1:06:00:00 - D2:06:00:00",
        params: {
          fromTimestamp: 86400n + 3600n * 6n,
          toTimestamp: 86400n + 86400n + 3600n * 6n,
          tiers: [
            { rate: (RATE_FACTOR / 100n) * 3n, cap: 1000000n }, // - 3% rate, cap 1000000
            { rate: (RATE_FACTOR / 100n) * 2n, cap: 1000000n }, // - 2% rate, cap 1000000
            { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n } // -------- 1% rate, no cap
          ],
          balance: 5000000n,
          streamYield: 1000000n
        },
        expected: {
          firstDayPartialYield:
            // FPD Total: 60000
            1000000n + // - Stream yield
            22500n + // --- T1: 3% on 1000000 for 18 hours (Initial balance)
            15000n + // --- T2: 2% on 2000000 for 18 hours (Initial balance)
            22500n, // ---- T3: 1% on 3000000 for 18 hours (Initial balance)
          fullDaysYield: 0n,
          lastDayPartialYield:
            // LPD Total: 22650
            7500n + // - T1: 3% on 1000000 for 6 hours (Initial balance)
            5000n + // - T2: 2% on 1000000 for 6 hours (Initial balance)
            7500n + // - T3: 1% on 3000000 for 6 hours (Initial balance)
            2500n + // - T3: 1% on 1000000 for 6 hours (Stream yield)
            150n, // --- T3: 1% on 60000 for 6 hours (FPD yield)
          tieredFirstDayPartialYield: [
            // FPD Total: 22500 + 15000 + 22500 = 60000
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n * 18n), // - FPD T1: 22500
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n * 18n), // - FPD T2: 15000
            simpleYield(3000000n, (RATE_FACTOR / 100n) * 1n, 3600n * 18n) // -- FPD T3: 22500
          ],
          tieredFullDaysYield: [0n, 0n, 0n],
          tieredLastDayPartialYield: [
            // LPD Total: 7500 + 5000 + 10105 = 22650
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 3n, 3600n * 6n), // - LPD T1: 7500
            simpleYield(1000000n, (RATE_FACTOR / 100n) * 2n, 3600n * 6n), // - LPD T2: 5000
            simpleYield(
              3000000n + // - Initial balance
              1000000n + // - Stream yield
              60000n, // ---- FPD yield
              RATE_FACTOR / 100n,
              3600n * 6n
            ) // ------------------------------------------------------------- LPD T3: 10105
          ]
        }
      }
    ];

    testCases.forEach((testCase, index) => {
      it(`Test case ${index + 1}: ${testCase.description}`, async function () {
        if (testCase.shouldRevert) {
          await expect(yieldStreamerTestable.compoundYield(testCase.params)).to.be.revertedWithCustomError(
            yieldStreamerTestable,
            testCase.revertMessage!
          );
        } else {
          const result = await yieldStreamerTestable.compoundYield(testCase.params);

          // Normalize the result for comparison
          const compoundYieldResult: YieldResult = {
            firstDayPartialYield: result.firstDayPartialYield,
            fullDaysYield: result.fullDaysYield,
            lastDayPartialYield: result.lastDayPartialYield,
            tieredFirstDayPartialYield: result.tieredFirstDayPartialYield.map((n: bigint) => n),
            tieredFullDaysYield: result.tieredFullDaysYield.map((n: bigint) => n),
            tieredLastDayPartialYield: result.tieredLastDayPartialYield.map((n: bigint) => n)
          };

          // Assertions
          expect(compoundYieldResult.tieredFirstDayPartialYield).to.deep.equal(
            testCase.expected.tieredFirstDayPartialYield
          );
          expect(compoundYieldResult.tieredFullDaysYield).to.deep.equal(testCase.expected.tieredFullDaysYield);
          expect(compoundYieldResult.tieredLastDayPartialYield).to.deep.equal(
            testCase.expected.tieredLastDayPartialYield
          );
          expect(compoundYieldResult.firstDayPartialYield).to.equal(testCase.expected.firstDayPartialYield);
          expect(compoundYieldResult.fullDaysYield).to.equal(testCase.expected.fullDaysYield);
          expect(compoundYieldResult.lastDayPartialYield).to.equal(testCase.expected.lastDayPartialYield);
        }
      });
    });
  });

  describe("Function 'calculateTieredFullDayYield()'", function () {
    let yieldStreamerTestable: Contract;

    beforeEach(async function () {
      const contracts = await setUpFixture(deployContracts);
      yieldStreamerTestable = contracts.yieldStreamerTestable;
    });

    const testCases = [
      {
        description: "Single Tier - zero cap",
        amount: 650000000n,
        tiers: [{ rate: (RATE_FACTOR / 100n) * 5n, cap: 0n }],
        expectedTieredYield: [(5n * 650000000n) / 100n]
      },
      {
        description: "Multiple Tiers - total caps are less than amount",
        amount: 650000000n,
        tiers: [
          { rate: (RATE_FACTOR / 100n) * 5n, cap: 300000000n },
          { rate: (RATE_FACTOR / 100n) * 3n, cap: 200000000n },
          { rate: (RATE_FACTOR / 100n) * 2n, cap: 100000000n },
          { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n }
        ],
        expectedTieredYield: [
          (5n * 300000000n) / 100n,
          (3n * 200000000n) / 100n,
          (2n * 100000000n) / 100n,
          (1n * 50000000n) / 100n
        ]
      },
      {
        description: "Multiple Tiers - total caps are greater than amount",
        amount: 450000000n,
        tiers: [
          { rate: (RATE_FACTOR / 100n) * 5n, cap: 300000000n },
          { rate: (RATE_FACTOR / 100n) * 3n, cap: 200000000n },
          { rate: (RATE_FACTOR / 100n) * 2n, cap: 100000000n },
          { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n }
        ],
        expectedTieredYield: [
          (5n * 300000000n) / 100n, // Tools: prevent Prettier from formatting this line
          (3n * 150000000n) / 100n,
          0n,
          0n
        ]
      },
      {
        description: "Multiple Tiers - zero rates present in the tiers array",
        amount: 650000000n,
        tiers: [
          { rate: 0n, cap: 300000000n },
          { rate: (RATE_FACTOR / 100n) * 2n, cap: 200000000n },
          { rate: 0n, cap: 100000000n },
          { rate: (RATE_FACTOR / 100n) * 1n, cap: 50000000n }
        ],
        expectedTieredYield: [
          0n, // Tools: prevent Prettier from formatting this line
          (2n * 200000000n) / 100n,
          0n,
          (1n * 50000000n) / 100n
        ]
      },
      {
        description: "Multiple Tiers - zero amount",
        amount: 0n,
        tiers: [
          { rate: (RATE_FACTOR / 100n) * 5n, cap: 300000000n },
          { rate: (RATE_FACTOR / 100n) * 3n, cap: 200000000n },
          { rate: (RATE_FACTOR / 100n) * 2n, cap: 100000000n },
          { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n }
        ],
        expectedTieredYield: [0n, 0n, 0n, 0n]
      }
    ];

    testCases.forEach(({ description, amount, tiers, expectedTieredYield }, index) => {
      it(`Test case ${index + 1}: ${description}`, async function () {
        const yieldResult = await yieldStreamerTestable.calculateTieredFullDayYield(amount, tiers);
        const expectedYield = expectedTieredYield.reduce((acc, curr) => acc + curr, 0n);
        const [fullDaysYield, tieredFullDaysYield] = normalizeYieldResult(yieldResult);
        expect(tieredFullDaysYield).to.deep.equal(expectedTieredYield);
        expect(fullDaysYield).to.equal(expectedYield);
      });
    });
  });

  describe("Function 'calculateTieredPartDayYield()'", function () {
    let yieldStreamerTestable: Contract;

    beforeEach(async function () {
      const contracts = await setUpFixture(deployContracts);
      yieldStreamerTestable = contracts.yieldStreamerTestable;
    });

    const testCases = [
      {
        description: "Single Tier - zero cap",
        amount: 650000000n,
        tiers: [{ rate: (RATE_FACTOR / 100n) * 5n, cap: 0n }],
        elapsedSeconds: 3600n,
        expectedTieredYield: [((RATE_FACTOR / 100n) * 5n * 650000000n * 3600n) / (DAY * RATE_FACTOR)]
      },
      {
        description: "Multiple Tiers - total caps are less than amount",
        amount: 650000000n,
        tiers: [
          { rate: (RATE_FACTOR / 100n) * 5n, cap: 300000000n },
          { rate: (RATE_FACTOR / 100n) * 3n, cap: 200000000n },
          { rate: (RATE_FACTOR / 100n) * 2n, cap: 100000000n },
          { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n }
        ],
        elapsedSeconds: 3600n,
        expectedTieredYield: [
          ((RATE_FACTOR / 100n) * 5n * 300000000n * 3600n) / (DAY * RATE_FACTOR),
          ((RATE_FACTOR / 100n) * 3n * 200000000n * 3600n) / (DAY * RATE_FACTOR),
          ((RATE_FACTOR / 100n) * 2n * 100000000n * 3600n) / (DAY * RATE_FACTOR),
          ((RATE_FACTOR / 100n) * 1n * 50000000n * 3600n) / (DAY * RATE_FACTOR)
        ]
      },
      {
        description: "Multiple Tiers - total caps are greater than amount",
        amount: 450000000n,
        tiers: [
          { rate: (RATE_FACTOR / 100n) * 5n, cap: 300000000n },
          { rate: (RATE_FACTOR / 100n) * 3n, cap: 200000000n },
          { rate: (RATE_FACTOR / 100n) * 2n, cap: 100000000n },
          { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n }
        ],
        elapsedSeconds: 3600n,
        expectedTieredYield: [
          ((RATE_FACTOR / 100n) * 5n * 300000000n * 3600n) / (DAY * RATE_FACTOR),
          ((RATE_FACTOR / 100n) * 3n * 150000000n * 3600n) / (DAY * RATE_FACTOR),
          0n,
          0n
        ]
      },
      {
        description: "Multiple Tiers - zero rates present in the tiers array",
        amount: 650000000n,
        tiers: [
          { rate: 0n, cap: 300000000n },
          { rate: (RATE_FACTOR / 100n) * 2n, cap: 200000000n },
          { rate: 0n, cap: 100000000n },
          { rate: (RATE_FACTOR / 100n) * 1n, cap: 50000000n }
        ],
        elapsedSeconds: 3600n,
        expectedTieredYield: [
          0n,
          ((RATE_FACTOR / 100n) * 2n * 200000000n * 3600n) / (DAY * RATE_FACTOR),
          0n,
          ((RATE_FACTOR / 100n) * 1n * 50000000n * 3600n) / (DAY * RATE_FACTOR)
        ]
      },
      {
        description: "Multiple Tiers - zero elapsed seconds",
        amount: 650000000n,
        tiers: [
          { rate: (RATE_FACTOR / 100n) * 5n, cap: 300000000n },
          { rate: (RATE_FACTOR / 100n) * 3n, cap: 200000000n },
          { rate: (RATE_FACTOR / 100n) * 2n, cap: 100000000n },
          { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n }
        ],
        elapsedSeconds: 0n,
        expectedTieredYield: [0n, 0n, 0n, 0n]
      },
      {
        description: "Multiple Tiers - zero amount",
        amount: 0n,
        tiers: [
          { rate: (RATE_FACTOR / 100n) * 5n, cap: 300000000n },
          { rate: (RATE_FACTOR / 100n) * 3n, cap: 200000000n },
          { rate: (RATE_FACTOR / 100n) * 2n, cap: 100000000n },
          { rate: (RATE_FACTOR / 100n) * 1n, cap: 0n }
        ],
        elapsedSeconds: 3600n,
        expectedTieredYield: [0n, 0n, 0n, 0n]
      }
    ];

    testCases.forEach(({ description, amount, tiers, elapsedSeconds, expectedTieredYield }, index) => {
      it(`Test case ${index + 1}: ${description}`, async function () {
        const yieldResult = await yieldStreamerTestable.calculateTieredPartDayYield(amount, tiers, elapsedSeconds);
        const expectedYield = expectedTieredYield.reduce((acc, curr) => acc + curr, 0n);
        const [partDayYield, tieredPartDayYield] = normalizeYieldResult(yieldResult);
        expect(tieredPartDayYield).to.deep.equal(expectedTieredYield);
        expect(partDayYield).to.equal(expectedYield);
      });
    });
  });

  describe("Function 'calculateSimpleFullDayYield()'", function () {
    let yieldStreamerTestable: Contract;

    beforeEach(async function () {
      const contracts = await setUpFixture(deployContracts);
      yieldStreamerTestable = contracts.yieldStreamerTestable;
    });

    it("Should return zero when amount is zero", async function () {
      const amount = 0n; // zero amount
      const rate = 1000n; // arbitrary non-zero rate
      const yieldResult = await yieldStreamerTestable.calculateSimpleFullDayYield(amount, rate);
      expect(yieldResult).to.equal(0);
    });

    it("Should return zero when rate is zero", async function () {
      const amount = 100n; // arbitrary non-zero amount
      const rate = 0n; // zero rate
      const yieldResult = await yieldStreamerTestable.calculateSimpleFullDayYield(amount, rate);
      expect(yieldResult).to.equal(0);
    });

    it("Should calculate yield correctly for typical values", async function () {
      const amount = 123456789n;
      const rate = 123456789n;
      const expectedYield = (amount * rate) / RATE_FACTOR;

      const yieldResult = await yieldStreamerTestable.calculateSimpleFullDayYield(amount, rate);
      expect(yieldResult).to.equal(expectedYield);
    });
  });

  describe("Function 'calculateSimplePartDayYield()'", function () {
    let yieldStreamerTestable: Contract;

    beforeEach(async function () {
      const contracts = await setUpFixture(deployContracts);
      yieldStreamerTestable = contracts.yieldStreamerTestable;
    });

    it("Should return zero when amount is zero", async function () {
      const amount = 0n; // zero amount
      const rate = 1000n; // arbitrary non-zero rate
      const elapsedSeconds = 3600n; // arbitrary non-zero elapsed seconds
      const yieldResult = await yieldStreamerTestable.calculateSimplePartDayYield(amount, rate, elapsedSeconds);
      expect(yieldResult).to.equal(0);
    });

    it("Should return zero when rate is zero", async function () {
      const amount = 1000n; // arbitrary non-zero amount
      const rate = 0n; // zero rate
      const elapsedSeconds = 3600n; // arbitrary non-zero elapsed seconds
      const yieldResult = await yieldStreamerTestable.calculateSimplePartDayYield(amount, rate, elapsedSeconds);
      expect(yieldResult).to.equal(0);
    });

    it("Should return zero when elapsedSeconds is zero", async function () {
      const amount = 1000n; // arbitrary non-zero amount
      const rate = 1000n; // arbitrary non-zero rate
      const elapsedSeconds = 0n; // zero elapsed seconds
      const yieldResult = await yieldStreamerTestable.calculateSimplePartDayYield(amount, rate, elapsedSeconds);
      expect(yieldResult).to.equal(0);
    });

    it("Should calculate partial day yield correctly", async function () {
      const amount = 123456789n; // arbitrary non-zero amount
      const rate = 123456789n; // arbitrary non-zero rate
      const elapsedSeconds = 12345n; // arbitrary non-zero elapsed seconds
      const expectedYield = (amount * rate * elapsedSeconds) / (86400n * RATE_FACTOR);

      const yieldResult = await yieldStreamerTestable.calculateSimplePartDayYield(amount, rate, elapsedSeconds);
      expect(yieldResult).to.equal(expectedYield);
    });

    it("Should calculate full day yield when elapsedSeconds equals 1 day", async function () {
      const amount = 123456789n; // arbitrary non-zero amount
      const rate = 123456789n; // arbitrary non-zero rate
      const elapsedSeconds = 86400n; // 1 day

      const expectedYield = (amount * rate * elapsedSeconds) / (86400n * RATE_FACTOR);

      const partialDayYieldResult = await yieldStreamerTestable.calculateSimplePartDayYield(
        amount,
        rate,
        elapsedSeconds
      );
      const fullDaysYieldResult = await yieldStreamerTestable.calculateSimpleFullDayYield(amount, rate);

      expect(partialDayYieldResult).to.equal(expectedYield);
      expect(fullDaysYieldResult).to.equal(expectedYield);
    });
  });

  describe("Function 'inRangeYieldRates()'", function () {
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
        fromTimestamp: -2n + secondRateEffectiveDay * DAY,
        toTimestamp: -1n + secondRateEffectiveDay * DAY,
        expectedStartIndex: 0,
        expectedEndIndex: 0
      },
      // Case 2:
      // - fromTimestamp is 1s before the second rate effective day
      // - toTimestamp is exactly on the second rate effective day
      // Expected: startIndex = 0, endIndex = 0
      {
        fromTimestamp: -1n + secondRateEffectiveDay * DAY,
        toTimestamp: 0n + secondRateEffectiveDay * DAY,
        expectedStartIndex: 0,
        expectedEndIndex: 0
      },
      // Case 3:
      // - fromTimestamp is 1s before the second rate effective day
      // - toTimestamp is 1s after the second rate effective day
      // Expected: startIndex = 0, endIndex = 1
      {
        fromTimestamp: -1n + secondRateEffectiveDay * DAY,
        toTimestamp: 1n + secondRateEffectiveDay * DAY,
        expectedStartIndex: 0,
        expectedEndIndex: 1
      },
      // Case 4:
      // - fromTimestamp is 1s before the second rate effective day
      // - toTimestamp is 1s before the third rate effective day
      // Expected: startIndex = 0, endIndex = 1
      {
        fromTimestamp: -1n + secondRateEffectiveDay * DAY,
        toTimestamp: -1n + thirdRateEffectiveDay * DAY,
        expectedStartIndex: 0,
        expectedEndIndex: 1
      },
      // Case 5:
      // - fromTimestamp is 1s before the second rate effective day
      // - toTimestamp is exactly on the third rate effective day
      // Expected: startIndex = 0, endIndex = 1
      {
        fromTimestamp: -1n + secondRateEffectiveDay * DAY,
        toTimestamp: 0n + thirdRateEffectiveDay * DAY,
        expectedStartIndex: 0,
        expectedEndIndex: 1
      },
      // Case 6:
      // - fromTimestamp is 1s before the second rate effective day
      // - toTimestamp is 1s after the third rate effective day
      // Expected: startIndex = 0, endIndex = 2
      {
        fromTimestamp: -1n + secondRateEffectiveDay * DAY,
        toTimestamp: 1n + thirdRateEffectiveDay * DAY,
        expectedStartIndex: 0,
        expectedEndIndex: 2
      },
      // Case 7:
      // - fromTimestamp is exactly on the second rate effective day
      // - toTimestamp is 1s after the third rate effective day
      // Expected: startIndex = 1, endIndex = 2
      {
        fromTimestamp: 0n + secondRateEffectiveDay * DAY,
        toTimestamp: 1n + thirdRateEffectiveDay * DAY,
        expectedStartIndex: 1,
        expectedEndIndex: 2
      },
      // Case 8:
      // - fromTimestamp is 1s after the second rate effective day
      // - toTimestamp is 1s after the third rate effective day
      // Expected: startIndex = 1, endIndex = 2
      {
        fromTimestamp: 1n + secondRateEffectiveDay * DAY,
        toTimestamp: 1n + thirdRateEffectiveDay * DAY,
        expectedStartIndex: 1,
        expectedEndIndex: 2
      },
      // Case 9:
      // - fromTimestamp is 1s before the third rate effective day
      // - toTimestamp is 1s after the third rate effective day
      // Expected: startIndex = 1, endIndex = 2
      {
        fromTimestamp: -1n + thirdRateEffectiveDay * DAY,
        toTimestamp: 1n + thirdRateEffectiveDay * DAY,
        expectedStartIndex: 1,
        expectedEndIndex: 2
      },
      // Case 10:
      // - fromTimestamp is exactly on the third rate effective day
      // - toTimestamp is 1s after the third rate effective day
      // Expected: startIndex = 2, endIndex = 2
      {
        fromTimestamp: 0n + thirdRateEffectiveDay * DAY,
        toTimestamp: 1n + thirdRateEffectiveDay * DAY,
        expectedStartIndex: 2,
        expectedEndIndex: 2
      },
      // Case 11:
      // - fromTimestamp is 1s after the third rate effective day
      // - toTimestamp is 2s after the third rate effective day
      // Expected: startIndex = 2, endIndex = 2
      {
        fromTimestamp: 1n + thirdRateEffectiveDay * DAY,
        toTimestamp: 2n + thirdRateEffectiveDay * DAY,
        expectedStartIndex: 2,
        expectedEndIndex: 2
      },
      // Case 12:
      // - fromTimestamp is exactly on the second rate effective day
      // - toTimestamp is 1s before the third rate effective day
      // Expected: startIndex = 1, endIndex = 1
      {
        fromTimestamp: 0n + secondRateEffectiveDay * DAY,
        toTimestamp: -1n + thirdRateEffectiveDay * DAY,
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
        firstDayPartialYield: 100n,
        fullDaysYield: 200n,
        lastDayPartialYield: 50n,
        tieredFirstDayPartialYield: [100n],
        tieredFullDaysYield: [200n],
        tieredLastDayPartialYield: [50n]
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
          firstDayPartialYield: 100n,
          fullDaysYield: 200n,
          lastDayPartialYield: 50n,
          tieredFirstDayPartialYield: [100n],
          tieredFullDaysYield: [200n],
          tieredLastDayPartialYield: [50n]
        },
        {
          firstDayPartialYield: 80n,
          fullDaysYield: 150n,
          lastDayPartialYield: 40n,
          tieredFirstDayPartialYield: [80n],
          tieredFullDaysYield: [150n],
          tieredLastDayPartialYield: [40n]
        },
        {
          firstDayPartialYield: 70n,
          fullDaysYield: 120n,
          lastDayPartialYield: 30n,
          tieredFirstDayPartialYield: [70n],
          tieredFullDaysYield: [120n],
          tieredLastDayPartialYield: [30n]
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
        0n,
        1n,
        50n,
        86399n,
        86400n,
        86401n,
        2n * 86400n,
        3n * 86400n + 12345n,
        1660135722n
      ];

      for (const ts of timestamps) {
        const nextDay = await yieldStreamerTestable.nextDay(ts);
        const expectedNextDay = ts - (ts % 86400n) + 86400n;
        expect(nextDay).to.equal(expectedNextDay);
      }
    });

    it("Should return the effective day as expected", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);

      const timestamps = [
        0n,
        1n,
        50n,
        86399n,
        86400n,
        86401n,
        2n * 86400n,
        3n * 86400n + 12345n,
        1660135722n
      ];

      for (const ts of timestamps) {
        const effectiveDay = await yieldStreamerTestable.effectiveDay(ts);
        const expectedDay = ts / 86400n;
        expect(effectiveDay).to.equal(expectedDay);
      }
    });

    it("Should return the remaining seconds as expected", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);

      const timestamps = [
        0n,
        1n,
        50n,
        86399n,
        86400n,
        86401n,
        2n * 86400n,
        3n * 86400n + 12345n,
        1660135722n
      ];

      for (const ts of timestamps) {
        const remainingSeconds = await yieldStreamerTestable.remainingSeconds(ts);
        const expectedRemainingSeconds = ts % 86400n;
        expect(remainingSeconds).to.equal(expectedRemainingSeconds);
      }
    });

    it("Should return the effective timestamp as expected", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);

      const timestamps = [
        0n,
        1n,
        50n,
        86399n,
        86400n,
        86401n,
        2n * 86400n,
        3n * 86400n + 12345n,
        1660135722n
      ];

      for (const ts of timestamps) {
        const effectiveTimestamp = await yieldStreamerTestable.effectiveTimestamp(ts);
        const expectedEffectiveTimestamp = (ts / 86400n) * 86400n;
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

      // Verify the function works as expected with hardcoded values.
      expect(await yieldStreamerTestable.roundDown(0n)).to.equal(0n);
      expect(await yieldStreamerTestable.roundDown(10000000n)).to.equal(10000000n);
      expect(await yieldStreamerTestable.roundDown(10000001n)).to.equal(10000000n);
      expect(await yieldStreamerTestable.roundDown(10009999n)).to.equal(10000000n);

      // Verify the function works as expected with the `roundDown` utility function.
      expect(await yieldStreamerTestable.roundDown(0n)).to.equal(roundDown(0n));
      expect(await yieldStreamerTestable.roundDown(10000000n)).to.equal(roundDown(10000000n));
      expect(await yieldStreamerTestable.roundDown(10000001n)).to.equal(roundDown(10000001n));
      expect(await yieldStreamerTestable.roundDown(10009999n)).to.equal(roundDown(10009999n));
    });
  });

  describe("Function 'roundUp()'", async () => {
    it("Should round up as expected", async () => {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);

      // Verify the function works as expected with hardcoded values.
      expect(await yieldStreamerTestable.roundUp(0n)).to.equal(0n);
      expect(await yieldStreamerTestable.roundUp(10000000n)).to.equal(10000000n);
      expect(await yieldStreamerTestable.roundUp(10000001n)).to.equal(10010000n);
      expect(await yieldStreamerTestable.roundUp(10009999n)).to.equal(10010000n);

      // Verify the function works as expected with the `roundUp` utility function.
      expect(await yieldStreamerTestable.roundUp(0n)).to.equal(roundUp(0n));
      expect(await yieldStreamerTestable.roundUp(10000000n)).to.equal(roundUp(10000000n));
      expect(await yieldStreamerTestable.roundUp(10000001n)).to.equal(roundUp(10000001n));
      expect(await yieldStreamerTestable.roundUp(10009999n)).to.equal(roundUp(10009999n));
    });
  });

  describe("Function 'map()'", async () => {
    it("Should map as expected", async () => {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);

      // Create an `AccruePreview` struct with sample data.
      const accruePreview: AccruePreview = {
        fromTimestamp: 10000000n,
        toTimestamp: 20000000n,
        balance: 30000000n,
        streamYieldBefore: 199996n,
        accruedYieldBefore: 299996n,
        streamYieldAfter: 499996n,
        accruedYieldAfter: 399996n,
        rates: [
          {
            tiers: [
              { rate: 101n, cap: 102n },
              { rate: 201n, cap: 202n }
            ],
            effectiveDay: 1n
          },
          {
            tiers: [
              { rate: 301n, cap: 302n },
              { rate: 401n, cap: 402n }
            ],
            effectiveDay: 9n
          }
        ],
        results: [
          {
            firstDayPartialYield: 111n,
            fullDaysYield: 211n,
            lastDayPartialYield: 311n,
            tieredFirstDayPartialYield: [101n, 10n],
            tieredFullDaysYield: [201n, 10n],
            tieredLastDayPartialYield: [301n, 10n]
          },
          {
            firstDayPartialYield: 411n,
            fullDaysYield: 511n,
            lastDayPartialYield: 611n,
            tieredFirstDayPartialYield: [401n, 10n],
            tieredFullDaysYield: [501n, 10n],
            tieredLastDayPartialYield: [601n, 10n]
          }
        ]
      };

      // Call the `map` function.
      const claimPreviewRaw: ClaimPreview = await yieldStreamerTestable.map(accruePreview);

      // Create the `ClaimPreview` struct with expected values.
      const expectedClaimPreview: ClaimPreview = {
        yield: roundDown(accruePreview.accruedYieldAfter + accruePreview.streamYieldAfter),
        balance: accruePreview.balance,
        fee: 0n,
        timestamp: accruePreview.toTimestamp,
        rates: accruePreview.rates[accruePreview.rates.length - 1].tiers.map(tier => tier.rate),
        caps: accruePreview.rates[accruePreview.rates.length - 1].tiers.map(tier => tier.cap)
      };

      // Verify the `ClaimPreview` struct is as expected.
      expect(expectedClaimPreview.yield).to.equal(claimPreviewRaw.yield);
      expect(expectedClaimPreview.fee).to.equal(claimPreviewRaw.fee);
      expect(expectedClaimPreview.timestamp).to.equal(claimPreviewRaw.timestamp);
      expect(expectedClaimPreview.balance).to.equal(claimPreviewRaw.balance);
      expect(expectedClaimPreview.rates).to.deep.equal(claimPreviewRaw.rates);
      expect(expectedClaimPreview.caps).to.deep.equal(claimPreviewRaw.caps);
    });
  });
});
