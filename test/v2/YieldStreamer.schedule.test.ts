import { expect } from "chai";
import { ethers, network, upgrades } from "hardhat";
import { Contract } from "ethers";
import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { checkEquality } from "../../test-utils/eth";

// Constants for rate calculations and time units
const RATE_FACTOR = BigInt(1000000000000); // Factor used in yield rate calculations (10^12)
const DAY = 24 * 60 * 60; // Number of seconds in a day
const HOUR = 60 * 60; // Number of seconds in an hour
const NEGATIVE_TIME_SHIFT = 3 * HOUR; // Negative time shift in seconds (3 hours)

// Interface representing an action (deposit or withdraw) in the test schedule
interface ActionItem {
  day: number; // Day number relative to the start time
  hour: number; // Hour of the day
  amount: bigint; // Amount to deposit or withdraw
  type: "deposit" | "withdraw"; // Type of action
}

// Interface representing the yield state expected after each action
interface YieldState {
  lastUpdateTimestamp: number; // Timestamp when the state was last updated
  lastUpdateBalance: bigint; // Balance at the last update
  accruedYield: bigint; // Total accrued yield up to the last update
  streamYield: bigint; // Yield that is being streamed since the last update
}

// Interface representing a yield rate change in the contract
interface YieldTieredRate {
  effectiveDay: number; // Day when the yield rate becomes effective
  tierRates: bigint[]; // Array of yield rate value for each tier (expressed in RATE_FACTOR units)
  tierCaps: bigint[]; // Array of balance cap for each tier
}

interface Version {
  major: number;
  minor: number;
  patch: number;

  [key: string]: number; // Indexing signature to ensure that fields are iterated over in a key-value style
}

/**
 * Calculates the adjusted block time aligned to the contract's internal time.
 * @returns The adjusted block time.
 */
async function getAdjustedBlockTime(): Promise<number> {
  const currentBlockTime = Number(await time.latest());
  let adjustedBlockTime = currentBlockTime - NEGATIVE_TIME_SHIFT;
  adjustedBlockTime = Math.floor(adjustedBlockTime / DAY) * DAY + DAY - 1;
  return adjustedBlockTime;
}

/**
 * Fetches the yield state of a given account from the contract.
 * @param yieldStreamer The YieldStreamer contract instance.
 * @param account The address of the account.
 * @returns The yield state of the account.
 */
async function getYieldState(yieldStreamer: Contract, account: string): Promise<YieldState> {
  const state = await yieldStreamer.getYieldState(account);
  return {
    lastUpdateTimestamp: state.lastUpdateTimestamp,
    lastUpdateBalance: state.lastUpdateBalance,
    accruedYield: state.accruedYield,
    streamYield: state.streamYield
  };
}

/**
 * Tests a schedule of deposit and withdraw actions against expected yield states.
 * @param user The signer representing the user performing actions.
 * @param yieldStreamer The YieldStreamer contract instance.
 * @param actionItems The list of actions to perform in the test.
 * @param expectedYieldStates The expected yield states after each action.
 */
async function testActionSchedule(
  user: SignerWithAddress,
  erc20Token: Contract,
  yieldStreamer: Contract,
  actionItems: ActionItem[],
  expectedYieldStates: YieldState[]
): Promise<void> {
  // Get the adjusted block time aligned to the contract's internal time
  const adjustedBlockTime = await getAdjustedBlockTime();

  // Calculate the start time (actual block timestamp)
  const startTime = adjustedBlockTime + NEGATIVE_TIME_SHIFT;

  // Set the block timestamp to the calculated start time
  await time.setNextBlockTimestamp(startTime);

  // Iterate over each action in the schedule
  for (const [index, actionItem] of actionItems.entries()) {
    // Calculate the desired internal timestamp for the action based on day and hour offsets
    const desiredInternalTimestamp = adjustedBlockTime + (actionItem.day - 1) * DAY + actionItem.hour * HOUR;

    // Adjust for NEGATIVE_TIME_SHIFT to set the block.timestamp
    const adjustedTimestamp = desiredInternalTimestamp + NEGATIVE_TIME_SHIFT;

    // Ensure the timestamp is strictly greater than the current block timestamp
    const currentBlockTimestamp = Number(await time.latest());
    const timestampToSet = adjustedTimestamp <= currentBlockTimestamp ? currentBlockTimestamp + 1 : adjustedTimestamp;

    // Increase the blockchain time to the desired adjusted timestamp
    await time.increaseTo(timestampToSet);

    // Perform the deposit or withdraw action based on the action type
    if (actionItem.type === "deposit") {
      // Perform a deposit action
      await erc20Token.connect(user).mint(user.address, actionItem.amount);
    } else if (actionItem.type === "withdraw") {
      // Perform a withdrawal action
      await erc20Token.connect(user).burn(user.address, actionItem.amount);
    }

    // Fetch the actual yield state from the contract after the action
    const contractYieldState = await getYieldState(yieldStreamer, user.address);

    // Update the expected lastUpdateTimestamp with the adjusted block timestamp
    const blockTimestamp = (await ethers.provider.getBlock("latest")).timestamp;
    expectedYieldStates[index].lastUpdateTimestamp = blockTimestamp - NEGATIVE_TIME_SHIFT;

    // Assert that the actual yield state matches the expected state
    expect(contractYieldState.lastUpdateTimestamp).to.equal(expectedYieldStates[index].lastUpdateTimestamp);
    expect(contractYieldState.lastUpdateBalance).to.equal(expectedYieldStates[index].lastUpdateBalance);
    expect(contractYieldState.accruedYield).to.equal(expectedYieldStates[index].accruedYield);
    expect(contractYieldState.streamYield).to.equal(expectedYieldStates[index].streamYield);
  }
}

/**
 * Adds yield rates to the contract's yield rate schedule.
 * @param yieldStreamer The YieldStreamer contract instance.
 * @param yieldRates The list of yield rates to add.
 */
async function addYieldRates(yieldStreamer: Contract, yieldRates: YieldTieredRate[]): Promise<void> {
  const zeroBytes32 = ethers.ZeroHash; // Placeholder for the yield rate ID
  for (const yieldRate of yieldRates) {
    await yieldStreamer.addYieldRate(zeroBytes32, yieldRate.effectiveDay, yieldRate.tierRates, yieldRate.tierCaps);
  }
}

/**
 * Calculates the effective day number for a yield rate based on the adjusted block time.
 * @param adjustedBlockTime The adjusted block time.
 * @param dayNumber The day number offset from the adjusted block time.
 * @returns The effective day number for the yield rate.
 */
function calculateEffectiveDay(adjustedBlockTime: number, dayNumber: number): number {
  return Math.floor((adjustedBlockTime + dayNumber * DAY) / DAY);
}

/**
 * Sets up a fixture for deploying contracts, using Hardhat's snapshot functionality.
 * @param func The async function that deploys and sets up the contracts.
 * @returns The deployed contracts.
 */
async function setUpFixture<T>(func: () => Promise<T>): Promise<T> {
  if (network.name === "hardhat") {
    // Use Hardhat's snapshot functionality for faster test execution
    return loadFixture(func);
  } else {
    // Directly execute the function if not on Hardhat network
    return func();
  }
}

describe("YieldStreamerV2 - Deposit/Withdraw Simulation Tests", function () {
  let user: SignerWithAddress;
  let adjustedBlockTime: number;
  const EXPECTED_VERSION: Version = {
    major: 2,
    minor: 0,
    patch: 0
  };

  // Get the signer representing the test user and adjusted block time before the tests run
  before(async function () {
    [user] = await ethers.getSigners();
    adjustedBlockTime = await getAdjustedBlockTime();
  });

  /**
   * Deploys the YieldStreamerV2 contract for testing.
   * @returns The deployed YieldStreamerV2 contract instance.
   */
  async function deployContracts(): Promise<{ erc20Token: Contract; yieldStreamer: Contract }> {
    const ERC20TokenMock = await ethers.getContractFactory("ERC20TokenMock");
    const YieldStreamerV2 = await ethers.getContractFactory("YieldStreamerV2");

    const erc20Token = await ERC20TokenMock.deploy("Mock Token", "MTK");
    await erc20Token.waitForDeployment();

    const yieldStreamer: Contract = await upgrades.deployProxy(YieldStreamerV2, [erc20Token.target]);
    await yieldStreamer.waitForDeployment();

    await erc20Token.setHook(yieldStreamer.target);

    return { erc20Token, yieldStreamer };
  }

  describe("Function 'deposit()'", function () {
    it("Should correctly update state for Deposit Schedule 1", async function () {
      const { erc20Token, yieldStreamer } = await setUpFixture(deployContracts);

      // Simulated action schedule of deposits
      const actionSchedule: ActionItem[] = [
        { day: 1, hour: 6, amount: BigInt(1000), type: "deposit" },
        { day: 1, hour: 12, amount: BigInt(1000), type: "deposit" },
        { day: 1, hour: 18, amount: BigInt(1000), type: "deposit" },
        { day: 2, hour: 6, amount: BigInt(1000), type: "deposit" },
        { day: 2, hour: 12, amount: BigInt(1000), type: "deposit" },
        { day: 2, hour: 18, amount: BigInt(1000), type: "deposit" },
        { day: 5, hour: 6, amount: BigInt(1000), type: "deposit" },
        { day: 5, hour: 12, amount: BigInt(1000), type: "deposit" },
        { day: 5, hour: 18, amount: BigInt(1000), type: "deposit" },
        { day: 6, hour: 6, amount: BigInt(1000), type: "deposit" },
        { day: 6, hour: 12, amount: BigInt(1000), type: "deposit" },
        { day: 6, hour: 18, amount: BigInt(1000), type: "deposit" }
      ];

      // Expected yield states after each action
      const expectedYieldStates: YieldState[] = [
        {
          // Action 1: Deposit 1000 at Day 1, 6 AM
          lastUpdateTimestamp: 0, // Will be updated during the test
          lastUpdateBalance: BigInt(1000),
          accruedYield: BigInt(0),
          streamYield: BigInt(0)
        },
        {
          // Action 2: Deposit 1000 at Day 1, 12 PM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(2000),
          accruedYield: BigInt(0),
          streamYield: BigInt(100) // Assuming yield accrual logic
        },
        {
          // Action 3, Deposit 1000 at Day 1, 6 PM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(3000),
          accruedYield: BigInt(0),
          streamYield: BigInt(300)
        },
        {
          // Action 4, Deposit 1000 at Day 2, 6 AM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(4000),
          accruedYield: BigInt(600),
          streamYield: BigInt(360)
        },
        {
          // Action 5, Deposit 1000 at Day 2, 12 PM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(5000),
          accruedYield: BigInt(600),
          streamYield: BigInt(820)
        },
        {
          // Action 6, Deposit 1000 at Day 2, 6 PM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(6000),
          accruedYield: BigInt(600),
          streamYield: BigInt(1380)
        },
        {
          // Action 7, Deposit 1000 at Day 5, 6 AM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(7000),
          accruedYield: BigInt(10934),
          streamYield: BigInt(1693)
        },
        {
          // Action 8, Deposit 1000 at Day 5, 12 PM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(8000),
          accruedYield: BigInt(10934),
          streamYield: BigInt(3486)
        },
        {
          // Action 9, Deposit 1000 at Day 5, 6 PM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(9000),
          accruedYield: BigInt(10934),
          streamYield: BigInt(5379)
        },
        {
          // Action 10, Deposit 1000 at Day 6, 6 AM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(10000),
          accruedYield: BigInt(18306),
          streamYield: BigInt(2730)
        },
        {
          // Action 11, Deposit 1000 at Day 6, 12 PM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(11000),
          accruedYield: BigInt(18306),
          streamYield: BigInt(5560)
        },
        {
          // Action 12, Deposit 1000 at Day 6, 6 PM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(12000),
          accruedYield: BigInt(18306),
          streamYield: BigInt(8490)
        }
      ];

      // Yield rates to be added to the contract
      const yieldRates: YieldTieredRate[] = [
        // 40% yield rate
        {
          effectiveDay: 0,
          tierRates: [(RATE_FACTOR * BigInt(40000)) / BigInt(100000), (RATE_FACTOR * BigInt(40000)) / BigInt(100000)],
          tierCaps: [BigInt(100), BigInt(0)]
        }
      ];

      // Set the initialized state for the user
      await yieldStreamer.setInitializedFlag(user.address, true);

      // Add yield rates to the contract
      await addYieldRates(yieldStreamer, yieldRates);

      // Run the action schedule and test the yield states
      await testActionSchedule(user, erc20Token, yieldStreamer, actionSchedule, expectedYieldStates);
    });

    it("Should correctly update state for Deposit Schedule 2", async () => {
      const { erc20Token, yieldStreamer } = await setUpFixture(deployContracts);

      // Simulated deposit schedule
      const actionSchedule: ActionItem[] = [
        { day: 1, hour: 6, amount: BigInt(1000), type: "deposit" },
        { day: 1, hour: 12, amount: BigInt(1000), type: "deposit" },
        { day: 1, hour: 18, amount: BigInt(1000), type: "deposit" },
        { day: 2, hour: 6, amount: BigInt(1000), type: "deposit" },
        { day: 2, hour: 12, amount: BigInt(1000), type: "deposit" },
        { day: 2, hour: 18, amount: BigInt(1000), type: "deposit" },
        { day: 5, hour: 6, amount: BigInt(1000), type: "deposit" },
        { day: 5, hour: 12, amount: BigInt(1000), type: "deposit" },
        { day: 5, hour: 18, amount: BigInt(1000), type: "deposit" },
        { day: 6, hour: 6, amount: BigInt(1000), type: "deposit" },
        { day: 6, hour: 12, amount: BigInt(1000), type: "deposit" },
        { day: 6, hour: 18, amount: BigInt(1000), type: "deposit" }
      ];

      // Expected YieldStates from the simulation
      const expectedYieldStates: YieldState[] = [
        {
          // Action 1, Deposit 1000 at Day 1, 6 AM
          lastUpdateTimestamp: 0, // Will be updated during the test
          lastUpdateBalance: BigInt(1000),
          accruedYield: BigInt(0),
          streamYield: BigInt(0)
        },
        {
          // Action 2, Deposit 1000 at Day 1, 12 PM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(2000),
          accruedYield: BigInt(0),
          streamYield: BigInt(100)
        },
        {
          // Action 3, Deposit 1000 at Day 1, 6 PM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(3000),
          accruedYield: BigInt(0),
          streamYield: BigInt(300)
        },
        {
          // Action 4, Deposit 1000 at Day 2, 6 AM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(4000),
          accruedYield: BigInt(600),
          streamYield: BigInt(360)
        },
        {
          // Action 5, Deposit 1000 at Day 2, 12 PM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(5000),
          accruedYield: BigInt(600),
          streamYield: BigInt(820)
        },
        {
          // Action 6, Deposit 1000 at Day 2, 6 PM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(6000),
          accruedYield: BigInt(600),
          streamYield: BigInt(1380)
        },
        {
          // Action 7, Deposit 1000 at Day 5, 6 AM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(7000),
          accruedYield: BigInt(21993),
          streamYield: BigInt(2799)
        },
        {
          // Action 8, Deposit 1000 at Day 5, 12 PM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(8000),
          accruedYield: BigInt(21993),
          streamYield: BigInt(5698)
        },
        {
          // Action 9, Deposit 1000 at Day 5, 6 PM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(9000),
          accruedYield: BigInt(21993),
          streamYield: BigInt(8697)
        },
        {
          // Action 10, Deposit 1000 at Day 6, 6 AM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(10000),
          accruedYield: BigInt(33789),
          streamYield: BigInt(4278)
        },
        {
          // Action 11, Deposit 1000 at Day 6, 12 PM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(11000),
          accruedYield: BigInt(33789),
          streamYield: BigInt(8656)
        },
        {
          // Action 12, Deposit 1000 at Day 6, 6 PM
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(12000),
          accruedYield: BigInt(33789),
          streamYield: BigInt(13134)
        }
      ];

      // Yield rates to be added to the contract
      const yieldRates: YieldTieredRate[] = [
        // 40% yield rate
        {
          effectiveDay: 0,
          tierRates: [(RATE_FACTOR * BigInt(40000)) / BigInt(100000), (RATE_FACTOR * BigInt(40000)) / BigInt(100000)],
          tierCaps: [BigInt(100), BigInt(0)]
        },
        // 80% yield rate
        {
          effectiveDay: calculateEffectiveDay(adjustedBlockTime, 3),
          tierRates: [(RATE_FACTOR * BigInt(80000)) / BigInt(100000), (RATE_FACTOR * BigInt(80000)) / BigInt(100000)],
          tierCaps: [BigInt(100), BigInt(0)]
        },
        // 40% yield rate
        {
          effectiveDay: calculateEffectiveDay(adjustedBlockTime, 5),
          tierRates: [(RATE_FACTOR * BigInt(40000)) / BigInt(100000), (RATE_FACTOR * BigInt(40000)) / BigInt(100000)],
          tierCaps: [BigInt(100), BigInt(0)]
        }
      ];

      // Set the initialized state for the user
      await yieldStreamer.setInitializedFlag(user.address, true);

      // Add yield rates to the contract
      await addYieldRates(yieldStreamer, yieldRates);

      // Run the action schedule and test the yield states
      await testActionSchedule(user, erc20Token, yieldStreamer, actionSchedule, expectedYieldStates);
    });
  });

  describe("Function 'withdraw()'", function () {
    it("Should correctly update state for Withdraw Schedule 1", async () => {
      const { erc20Token, yieldStreamer } = await setUpFixture(deployContracts);

      // Simulated action schedule of deposits and withdrawals
      const actionSchedule: ActionItem[] = [
        { day: 1, hour: 6, amount: BigInt(11000), type: "deposit" },
        { day: 1, hour: 12, amount: BigInt(1000), type: "withdraw" },
        { day: 1, hour: 18, amount: BigInt(1000), type: "withdraw" },
        { day: 2, hour: 6, amount: BigInt(1000), type: "withdraw" },
        { day: 2, hour: 12, amount: BigInt(1000), type: "withdraw" },
        { day: 2, hour: 18, amount: BigInt(1000), type: "withdraw" },
        { day: 5, hour: 6, amount: BigInt(1000), type: "withdraw" },
        { day: 5, hour: 12, amount: BigInt(1000), type: "withdraw" },
        { day: 5, hour: 18, amount: BigInt(1000), type: "withdraw" },
        { day: 6, hour: 6, amount: BigInt(1000), type: "withdraw" },
        { day: 6, hour: 12, amount: BigInt(1000), type: "withdraw" },
        { day: 6, hour: 18, amount: BigInt(1000), type: "withdraw" }
      ];

      // Expected yield states after each action
      const expectedYieldStates: YieldState[] = [
        {
          // Action 1, Day 1, 6 AM, Deposit 11000
          lastUpdateTimestamp: 0, // Will be updated during the test
          lastUpdateBalance: BigInt(11000),
          accruedYield: BigInt(0),
          streamYield: BigInt(0)
        },
        {
          // Action 2, Day 1, 12 PM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(10000),
          accruedYield: BigInt(0),
          streamYield: BigInt(1100)
        },
        {
          // Action 3, Day 1, 6 PM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(9000),
          accruedYield: BigInt(0),
          streamYield: BigInt(2100)
        },
        {
          // Action 4, Day 2, 6 AM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(8000),
          accruedYield: BigInt(3000),
          streamYield: BigInt(1200)
        },
        {
          // Action 5, Day 2, 12 PM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(7000),
          accruedYield: BigInt(3000),
          streamYield: BigInt(2300)
        },
        {
          // Action 6, Day 2, 6 PM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(6000),
          accruedYield: BigInt(3000),
          streamYield: BigInt(3300)
        },
        {
          // Action 7, Day 5, 6 AM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(5000),
          accruedYield: BigInt(19872),
          streamYield: BigInt(2587)
        },
        {
          // Action 8, Day 5, 12 PM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(4000),
          accruedYield: BigInt(19872),
          streamYield: BigInt(5074)
        },
        {
          // Action 9, Day 5, 6 PM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(3000),
          accruedYield: BigInt(19872),
          streamYield: BigInt(7461)
        },
        {
          // Action 10, Day 6, 6 AM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(2000),
          accruedYield: BigInt(29620),
          streamYield: BigInt(3262)
        },
        {
          // Action 11, Day 6, 12 PM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(1000),
          accruedYield: BigInt(29620),
          streamYield: BigInt(6424)
        },
        {
          // Action 12, Day 6, 6 PM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(0),
          accruedYield: BigInt(29620),
          streamYield: BigInt(9486)
        }
      ];

      // Yield rates to be added to the contract
      const yieldRates: YieldTieredRate[] = [
        // 40% yield rate
        {
          effectiveDay: 0,
          tierRates: [(RATE_FACTOR * BigInt(40000)) / BigInt(100000), (RATE_FACTOR * BigInt(40000)) / BigInt(100000)],
          tierCaps: [BigInt(100), BigInt(0)]
        }
      ];

      // Set the initialized state for the user
      await yieldStreamer.setInitializedFlag(user.address, true);

      // Add yield rates to the contract
      await addYieldRates(yieldStreamer, yieldRates);

      // Run the action schedule and test the yield states
      await testActionSchedule(user, erc20Token, yieldStreamer, actionSchedule, expectedYieldStates);
    });

    it("Should correctly update state for Withdraw Schedule 2", async () => {
      const { erc20Token, yieldStreamer } = await setUpFixture(deployContracts);

      // Simulated action schedule
      const actionSchedule: ActionItem[] = [
        { day: 1, hour: 6, amount: BigInt(11000), type: "deposit" },
        { day: 1, hour: 12, amount: BigInt(1000), type: "withdraw" },
        { day: 1, hour: 18, amount: BigInt(1000), type: "withdraw" },
        { day: 2, hour: 6, amount: BigInt(1000), type: "withdraw" },
        { day: 2, hour: 12, amount: BigInt(1000), type: "withdraw" },
        { day: 2, hour: 18, amount: BigInt(1000), type: "withdraw" },
        { day: 5, hour: 6, amount: BigInt(1000), type: "withdraw" },
        { day: 5, hour: 12, amount: BigInt(1000), type: "withdraw" },
        { day: 5, hour: 18, amount: BigInt(1000), type: "withdraw" },
        { day: 6, hour: 6, amount: BigInt(1000), type: "withdraw" },
        { day: 6, hour: 12, amount: BigInt(1000), type: "withdraw" },
        { day: 6, hour: 18, amount: BigInt(1000), type: "withdraw" }
      ];

      // Expected YieldStates from the simulation
      const expectedYieldStates: YieldState[] = [
        {
          // Action 1, Day 1, 6 AM, Deposit 11000
          lastUpdateTimestamp: 0, // Will be updated during the test
          lastUpdateBalance: BigInt(11000),
          accruedYield: BigInt(0),
          streamYield: BigInt(0)
        },
        {
          // Action 2, Day 1, 12 PM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(10000),
          accruedYield: BigInt(0),
          streamYield: BigInt(1100)
        },
        {
          // Action 3, Day 1, 6 PM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(9000),
          accruedYield: BigInt(0),
          streamYield: BigInt(2100)
        },
        {
          // Action 4, Day 2, 6 AM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(8000),
          accruedYield: BigInt(3000),
          streamYield: BigInt(1200)
        },
        {
          // Action 5, Day 2, 12 PM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(7000),
          accruedYield: BigInt(3000),
          streamYield: BigInt(2300)
        },
        {
          // Action 6, Day 2, 6 PM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(6000),
          accruedYield: BigInt(3000),
          streamYield: BigInt(3300)
        },
        {
          // Action 7, Day 5, 6 AM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(5000),
          accruedYield: BigInt(36768),
          streamYield: BigInt(4276)
        },
        {
          // Action 8, Day 5, 12 PM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(4000),
          accruedYield: BigInt(36768),
          streamYield: BigInt(8452)
        },
        {
          // Action 9, Day 5, 6 PM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(3000),
          accruedYield: BigInt(36768),
          streamYield: BigInt(12528)
        },
        {
          // Action 10, Day 6, 6 AM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(2000),
          accruedYield: BigInt(53272),
          streamYield: BigInt(5627)
        },
        {
          // Action 11, Day 6, 12 PM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(1000),
          accruedYield: BigInt(53272),
          streamYield: BigInt(11154)
        },
        {
          // Action 12, Day 6, 6 PM, Withdraw 1000
          lastUpdateTimestamp: 0,
          lastUpdateBalance: BigInt(0),
          accruedYield: BigInt(53272),
          streamYield: BigInt(16581)
        }
      ];

      // Yield rates to be added to the contract
      const yieldRates: YieldTieredRate[] = [
        // 40% yield rate
        {
          effectiveDay: 0,
          tierRates: [(RATE_FACTOR * BigInt(40000)) / BigInt(100000), (RATE_FACTOR * BigInt(40000)) / BigInt(100000)],
          tierCaps: [BigInt(100), BigInt(0)]
        },
        // 80% yield rate
        {
          effectiveDay: calculateEffectiveDay(adjustedBlockTime, 3),
          tierRates: [(RATE_FACTOR * BigInt(80000)) / BigInt(100000), (RATE_FACTOR * BigInt(80000)) / BigInt(100000)],
          tierCaps: [BigInt(100), BigInt(0)]
        },
        // 40% yield rate
        {
          effectiveDay: calculateEffectiveDay(adjustedBlockTime, 5),
          tierRates: [(RATE_FACTOR * BigInt(40000)) / BigInt(100000), (RATE_FACTOR * BigInt(40000)) / BigInt(100000)],
          tierCaps: [BigInt(100), BigInt(0)]
        }
      ];

      // Set the initialized state for the user
      await yieldStreamer.setInitializedFlag(user.address, true);

      // Add yield rates to the contract
      await addYieldRates(yieldStreamer, yieldRates);

      // Run the action schedule and test the yield states
      await testActionSchedule(user, erc20Token, yieldStreamer, actionSchedule, expectedYieldStates);
    });
  });

  describe("Function '$__VERSION()'", async () => {
    it("Returns expected values", async () => {
      const { yieldStreamer} = await setUpFixture(deployContracts);
      const yieldStreamerVersion = await yieldStreamer.$__VERSION();
      checkEquality(yieldStreamerVersion, EXPECTED_VERSION);
    });
  });
});
