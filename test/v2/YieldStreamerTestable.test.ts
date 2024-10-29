import { expect } from "chai";
import { ethers, network, upgrades } from "hardhat";
import { Contract, ContractFactory } from "ethers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

const ROUND_FACTOR = 10000;

interface RateTier {
  rate: bigint;
  cap: bigint;
}

interface YieldTieredRate {
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
  rates: YieldTieredRate[];
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

    const yieldStreamerTestable: Contract = await upgrades.deployProxy(
      yieldStreamerTestableFactory,
      [tokenMock.target]
    );
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
  ): Promise<YieldTieredRate[]> {
    const rates: YieldTieredRate[] = [];

    // Build the yield tiered rates array.
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

    // Add the rates to the contract.
    for (const rate of rates) {
      const ratesArray = rate.tiers.map(tier => tier.rate);
      const capsArray = rate.tiers.map(tier => tier.cap);
      await yieldStreamerTestable.addYieldRate(groupId, rate.effectiveDay, ratesArray, capsArray);
    }

    return rates;
  }

  function normalizeYieldRates(rates: any[]): YieldTieredRate[] {
    return rates.map((rate: any) => ({
      effectiveDay: BigInt(rate[1]),
      tiers: rate[0].map((tier: any) => ({
        rate: BigInt(tier[0]),
        cap: BigInt(tier[1])
      }))
    }));
  }

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
