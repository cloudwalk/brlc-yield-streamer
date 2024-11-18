import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Contract, ContractFactory } from "ethers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { getAddress, getLatestBlockTimestamp, proveTx } from "../test-utils/eth";
import { setUpFixture } from "../test-utils/common";

// Constants for rate calculations and time units
const SECONDS_IN_DAY = 24 * 60 * 60; // Number of seconds in a day

const BYTES32_ZERO = ethers.ZeroHash;
const ADDRESS_ZERO = ethers.ZeroAddress;

const RATE_FACTOR = 10 ** 12;
const ROUND_FACTOR = 10000;
const FEE_RATE = 0;
const NEGATIVE_TIME_SHIFT = 3 * 60 * 60;
const MIN_CLAIM_AMOUNT = 1000000;
const ENABLE_YIELD_STATE_AUTO_INITIALIZATION = false;

interface RateTier {
  rate: bigint;
  cap: bigint;
}

interface YieldRate {
  tiers: RateTier[];
  effectiveDay: bigint;
}

interface YieldState {
  flags: number;
  streamYield: bigint;
  accruedYield: bigint;
  lastUpdateTimestamp: bigint;
  lastUpdateBalance: bigint;
}

interface YieldStreamerHarnessLayout {
  currentBlockTimestamp: bigint;
  usingSpecialBlockTimestamps: boolean;
}

interface Version {
  major: number;
  minor: number;
  patch: number;
}

function checkEquality<T extends Record<string, unknown>>(actualObject: T, expectedObject: T, index?: number) {
  const indexString = !index ? "" : ` with index: ${index}`;
  Object.keys(expectedObject).forEach(property => {
    const value = actualObject[property];
    if (typeof value === "undefined" || typeof value === "function" || typeof value === "object") {
      throw Error(`Property "${property}" is not found in the actual object` + indexString);
    }
    expect(value).to.eq(
      expectedObject[property],
      `Mismatch in the "${property}" property between the actual object and expected one` + indexString
    );
  });
}

describe("YieldStreamerHarness", function () {
  // Errors of the lib contracts
  const REVERT_ERROR_IF_CONTRACT_INITIALIZATION_IS_INVALID = "InvalidInitialization";

  // Errors of the contracts under test
  const REVERT_ERROR_IF_TOKEN_ADDRESS_IS_ZERO = "YieldStreamer_TokenAddressZero";

  let yieldStreamerHarnessFactory: ContractFactory;
  let deployer: HardhatEthersSigner;

  const ownerRole: string = ethers.id("OWNER_ROLE");
  const pauserRole: string = ethers.id("PAUSER_ROLE");
  const rescuerRole: string = ethers.id("RESCUER_ROLE");
  const harnessAdminRole: string = ethers.id("HARNESS_ADMIN_ROLE");
  const EXPECTED_VERSION: Version = {
    major: 2,
    minor: 0,
    patch: 0
  };

  // Get the signer representing the test user before the tests run
  before(async function () {
    [deployer] = await ethers.getSigners();

    // Contract factories with the explicitly specified deployer account
    yieldStreamerHarnessFactory = await ethers.getContractFactory("YieldStreamerHarness");
  });

  async function deployContracts(): Promise<{ yieldStreamerHarness: Contract; tokenMock: Contract }> {
    const tokenMockFactory = await ethers.getContractFactory("ERC20TokenMock");

    const tokenMock = await tokenMockFactory.deploy("Mock Token", "MTK");
    await tokenMock.waitForDeployment();

    const yieldStreamerHarness: Contract = await upgrades.deployProxy(yieldStreamerHarnessFactory, [tokenMock.target]);
    await yieldStreamerHarness.waitForDeployment();

    await tokenMock.setHook(yieldStreamerHarness.target);

    return { yieldStreamerHarness, tokenMock };
  }

  async function deployAndConfigureContracts(): Promise<{ yieldStreamerHarness: Contract; tokenMock: Contract }> {
    const { yieldStreamerHarness, tokenMock } = await deployContracts();
    await proveTx(yieldStreamerHarness.initHarness());
    await proveTx(yieldStreamerHarness.grantRole(harnessAdminRole, deployer.address));
    return { yieldStreamerHarness, tokenMock };
  }

  describe("Function 'initialize()'", async () => {
    it("Configures the contract as expected", async () => {
      const { yieldStreamerHarness, tokenMock } = await setUpFixture(deployContracts);

      // The underlying token contract address
      expect(await yieldStreamerHarness.underlyingToken()).to.equal(getAddress(tokenMock));

      // Role hashes
      expect(await yieldStreamerHarness.OWNER_ROLE()).to.equal(ownerRole);
      expect(await yieldStreamerHarness.PAUSER_ROLE()).to.equal(pauserRole);
      expect(await yieldStreamerHarness.RESCUER_ROLE()).to.equal(rescuerRole);
      expect(await yieldStreamerHarness.HARNESS_ADMIN_ROLE()).to.equal(harnessAdminRole);

      // The role admins
      expect(await yieldStreamerHarness.getRoleAdmin(ownerRole)).to.equal(ownerRole);
      expect(await yieldStreamerHarness.getRoleAdmin(pauserRole)).to.equal(ownerRole);
      expect(await yieldStreamerHarness.getRoleAdmin(rescuerRole)).to.equal(ownerRole);
      expect(await yieldStreamerHarness.getRoleAdmin(harnessAdminRole)).to.equal(BYTES32_ZERO);

      // The deployer should have the owner role, but not the other roles
      expect(await yieldStreamerHarness.hasRole(ownerRole, deployer.address)).to.equal(true);
      expect(await yieldStreamerHarness.hasRole(pauserRole, deployer.address)).to.equal(false);
      expect(await yieldStreamerHarness.hasRole(rescuerRole, deployer.address)).to.equal(false);
      expect(await yieldStreamerHarness.hasRole(harnessAdminRole, deployer.address)).to.equal(false);

      // The initial contract state is unpaused
      expect(await yieldStreamerHarness.paused()).to.equal(false);

      // Other parameters and constants
      expect(await yieldStreamerHarness.RATE_FACTOR()).to.equal(RATE_FACTOR);
      expect(await yieldStreamerHarness.ROUND_FACTOR()).to.equal(ROUND_FACTOR);
      expect(await yieldStreamerHarness.FEE_RATE()).to.equal(FEE_RATE);
      expect(await yieldStreamerHarness.NEGATIVE_TIME_SHIFT()).to.equal(NEGATIVE_TIME_SHIFT);
      expect(await yieldStreamerHarness.MIN_CLAIM_AMOUNT()).to.equal(MIN_CLAIM_AMOUNT);
      expect(await yieldStreamerHarness.ENABLE_YIELD_STATE_AUTO_INITIALIZATION()).to.equal(
        ENABLE_YIELD_STATE_AUTO_INITIALIZATION
      );
    });

    it("Is reverted if it is called a second time ", async () => {
      const { yieldStreamerHarness, tokenMock } = await setUpFixture(deployContracts);
      await expect(yieldStreamerHarness.initialize(getAddress(tokenMock))).to.be.revertedWithCustomError(
        yieldStreamerHarness,
        REVERT_ERROR_IF_CONTRACT_INITIALIZATION_IS_INVALID
      );
    });

    it("Is reverted if the passed token address is zero", async () => {
      const anotherFreezerRoot: Contract = await upgrades.deployProxy(yieldStreamerHarnessFactory, [], {
        initializer: false
      });

      await expect(anotherFreezerRoot.initialize(ADDRESS_ZERO)).to.be.revertedWithCustomError(
        yieldStreamerHarnessFactory,
        REVERT_ERROR_IF_TOKEN_ADDRESS_IS_ZERO
      );
    });
  });

  describe("Function '$__VERSION()'", async () => {
    it("Returns expected values", async () => {
      const { yieldStreamerHarness } = await setUpFixture(deployContracts);
      const yieldStreamerHarnessVersion = await yieldStreamerHarness.$__VERSION();
      checkEquality(yieldStreamerHarnessVersion, EXPECTED_VERSION);
    });
  });

  describe("Function 'initHarness()'", async () => {
    it("Executes as expected", async () => {
      const { yieldStreamerHarness } = await setUpFixture(deployContracts);
      await proveTx(yieldStreamerHarness.initHarness());
      expect(await yieldStreamerHarness.getRoleAdmin(harnessAdminRole)).to.equal(ownerRole);
    });
  });

  describe("Function 'deleteYieldRates()'", async () => {
    it("Executes as expected", async () => {
      const { yieldStreamerHarness } = await setUpFixture(deployAndConfigureContracts);
      const groupId = 1;
      const yieldRate1: YieldRate = { effectiveDay: 0n, tiers: [{ rate: 123n, cap: 0n }] };
      const yieldRate2: YieldRate = { effectiveDay: 1n, tiers: [{ rate: 456n, cap: 0n }] };

      const actualYieldRatesBefore1 = await yieldStreamerHarness.getGroupYieldRates(groupId);
      expect(actualYieldRatesBefore1.length).to.equal(0);

      await proveTx(
        yieldStreamerHarness.addYieldRate(
          groupId,
          yieldRate1.effectiveDay,
          yieldRate1.tiers.map(tier => tier.rate),
          yieldRate1.tiers.map(tier => tier.cap)
        )
      );
      await proveTx(
        yieldStreamerHarness.addYieldRate(
          groupId,
          yieldRate2.effectiveDay,
          yieldRate2.tiers.map(tier => tier.rate),
          yieldRate2.tiers.map(tier => tier.cap)
        )
      );

      const actualYieldRatesBefore2 = await yieldStreamerHarness.getGroupYieldRates(groupId);
      expect(actualYieldRatesBefore2.length).to.equal(2);

      await proveTx(yieldStreamerHarness.deleteYieldRates(groupId));
      const actualYieldRatesAfter = await yieldStreamerHarness.getGroupYieldRates(groupId);
      expect(actualYieldRatesAfter.length).to.equal(0);
    });
  });

  describe("Function 'setYieldState()'", async () => {
    it("Executes as expected", async () => {
      const { yieldStreamerHarness } = await setUpFixture(deployAndConfigureContracts);
      const accountAddress = "0x0000000000000000000000000000000000000001";
      const yieldState: YieldState = {
        flags: 0xff,
        streamYield: 2n ** 64n - 1n,
        accruedYield: 2n ** 64n - 1n,
        lastUpdateTimestamp: 2n ** 40n - 1n,
        lastUpdateBalance: 2n ** 64n - 1n
      };
      await proveTx(yieldStreamerHarness.setYieldState(accountAddress, yieldState));
      const actualYieldState = await yieldStreamerHarness.getYieldState(accountAddress);
      checkEquality(actualYieldState, yieldState);
    });
  });

  describe("Function 'resetYieldState()'", async () => {
    it("Executes as expected", async () => {
      const { yieldStreamerHarness } = await setUpFixture(deployAndConfigureContracts);
      const accountAddress = "0x0000000000000000000000000000000000000001";
      const yieldStateBefore: YieldState = {
        flags: 0xff,
        streamYield: 2n ** 64n - 1n,
        accruedYield: 2n ** 64n - 1n,
        lastUpdateTimestamp: 2n ** 40n - 1n,
        lastUpdateBalance: 2n ** 64n - 1n
      };
      await proveTx(yieldStreamerHarness.setYieldState(accountAddress, yieldStateBefore));
      const actualYieldStateBefore = await yieldStreamerHarness.getYieldState(accountAddress);
      checkEquality(actualYieldStateBefore, yieldStateBefore);

      const yieldStateAfter: YieldState = {
        flags: 0,
        streamYield: 0n,
        accruedYield: 0n,
        lastUpdateTimestamp: 0n,
        lastUpdateBalance: 0n
      };
      await proveTx(yieldStreamerHarness.resetYieldState(accountAddress));
      const actualYieldStateAfter = await yieldStreamerHarness.getYieldState(accountAddress);
      checkEquality(actualYieldStateAfter, yieldStateAfter);
    });
  });

  describe("Function 'setBlockTimestamp()'", async () => {
    it("Executes as expected", async () => {
      const { yieldStreamerHarness } = await setUpFixture(deployAndConfigureContracts);
      const day = 123;
      const time = 456;
      const expectedTimestamp = day * SECONDS_IN_DAY + time;
      const expectedYieldStreamerHarnessLayout: YieldStreamerHarnessLayout = {
        currentBlockTimestamp: BigInt(expectedTimestamp),
        usingSpecialBlockTimestamps: false
      };

      await proveTx(yieldStreamerHarness.setBlockTimestamp(day, time));

      const actualYieldStreamerHarnessLayout = await yieldStreamerHarness.getHarnessStorageLayout();
      checkEquality(actualYieldStreamerHarnessLayout, expectedYieldStreamerHarnessLayout);
    });
  });

  describe("Function 'blockTimestamp()'", async () => {
    it("Executes as expected", async () => {
      const { yieldStreamerHarness } = await setUpFixture(deployAndConfigureContracts);
      const day = 123;
      const time = 456;

      let expectedBlockTimestamp = (await getLatestBlockTimestamp()) - NEGATIVE_TIME_SHIFT;
      expect(await yieldStreamerHarness.blockTimestamp()).to.equal(expectedBlockTimestamp);

      await proveTx(yieldStreamerHarness.setUsingSpecialBlockTimestamps(true));
      expectedBlockTimestamp = 0;
      expect(await yieldStreamerHarness.blockTimestamp()).to.equal(expectedBlockTimestamp);

      await proveTx(yieldStreamerHarness.setBlockTimestamp(day, time));
      expectedBlockTimestamp = day * SECONDS_IN_DAY + time - NEGATIVE_TIME_SHIFT;
      expect(await yieldStreamerHarness.blockTimestamp()).to.equal(expectedBlockTimestamp);
    });
  });
});
