import { expect } from "chai";
import { ethers, network, upgrades } from "hardhat";
import { Contract, ContractFactory } from "ethers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";

const ROUND_FACTOR = 10000;

interface YieldRate {
  effectiveDay: bigint;
  value: bigint;
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
  rate: bigint;
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

  function generateSampleYieldRates(count: number): YieldRate[] {
    const rates: YieldRate[] = [];
    for (let i = 0; i < count; i++) {
      rates.push({
        effectiveDay: BigInt(i + 1),
        value: BigInt(100 + i * 10)
      });
    }
    return rates;
  }

  function normalizeYieldRates(rates: any[]): YieldRate[] {
    return rates.map((rate: any) => ({
      effectiveDay: BigInt(rate[0]),
      value: BigInt(rate[1])
    }));
  }

  describe("Function 'truncateArray()'", function () {
    it("Should return the full array when startIndex is 0 and endIndex is rates.length - 1", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);
      const rates = generateSampleYieldRates(5);
      const truncatedRatesRaw = await yieldStreamerTestable.truncateArray(0, rates.length - 1, rates);
      const truncatedRates = normalizeYieldRates(truncatedRatesRaw);
      expect(truncatedRates).to.deep.equal(rates);
    });

    it("Should return a truncated array when startIndex and endIndex are different", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);
      const rates = generateSampleYieldRates(5);
      const truncatedRatesRaw = await yieldStreamerTestable.truncateArray(1, 3, rates);
      const truncatedRates = normalizeYieldRates(truncatedRatesRaw);
      expect(truncatedRates).to.deep.equal(rates.slice(1, 4));
    });

    it("Should return a single element when startIndex and endIndex are the same (multiple rates in array)", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);
      const rates = generateSampleYieldRates(5);
      const index = 2;
      const truncatedRatesRaw = await yieldStreamerTestable.truncateArray(index, index, rates);
      const truncatedRates = normalizeYieldRates(truncatedRatesRaw);
      expect(truncatedRates.length).to.equal(1);
      expect(truncatedRates[0]).to.deep.equal(rates[index]);
    });

    it("Should return a single element when startIndex and endIndex are the same (single rate in array)", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);
      const rates = generateSampleYieldRates(1);
      const index = 0;
      const truncatedRatesRaw = await yieldStreamerTestable.truncateArray(index, index, rates);
      const truncatedRates = normalizeYieldRates(truncatedRatesRaw);
      expect(truncatedRates.length).to.equal(1);
      expect(truncatedRates[0]).to.deep.equal(rates[index]);
    });

    it("Should revert when startIndex is greater than endIndex", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);
      const rates = generateSampleYieldRates(5);
      await expect(yieldStreamerTestable.truncateArray(3, 2, rates)).to.be.revertedWithPanic(0x11); // Arithmetic operation overflowed outside of an unchecked block
    });

    it("Should revert when startIndex is out of bounds", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);
      const rates = generateSampleYieldRates(5);
      await expect(yieldStreamerTestable.truncateArray(rates.length, rates.length, rates)).to.be.revertedWithPanic(
        0x32
      ); // Array accessed at an out-of-bounds or negative index
    });

    it("Should revert when endIndex is out of bounds", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);
      const rates = generateSampleYieldRates(5);
      await expect(yieldStreamerTestable.truncateArray(0, rates.length, rates)).to.be.revertedWithPanic(0x32); // Array accessed at an out-of-bounds or negative index
    });

    it("Should revert when rates array is empty", async function () {
      const { yieldStreamerTestable } = await setUpFixture(deployContracts);
      const rates: YieldRate[] = [];
      await expect(yieldStreamerTestable.truncateArray(0, 0, rates)).to.be.revertedWithPanic(0x32); // Array accessed at an out-of-bounds or negative index
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
            effectiveDay: BigInt("1"),
            value: BigInt("100")
          },
          {
            effectiveDay: BigInt("9"),
            value: BigInt("200")
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
        rate: accruePreview.rates[accruePreview.rates.length - 1].value
      };

      // Verify the return values.
      expect(expectedClaimPreview.yield).to.equal(claimPreviewRaw.yield);
      expect(expectedClaimPreview.fee).to.equal(claimPreviewRaw.fee);
      expect(expectedClaimPreview.timestamp).to.equal(claimPreviewRaw.timestamp);
      expect(expectedClaimPreview.balance).to.equal(claimPreviewRaw.balance);
      expect(expectedClaimPreview.rate).to.equal(claimPreviewRaw.rate);
    });
  });
});
