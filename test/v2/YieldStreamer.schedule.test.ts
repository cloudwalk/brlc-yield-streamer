import { expect } from "chai";
import { ethers, network, upgrades } from "hardhat";
import { Contract } from "ethers";
import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

// Constants for rate calculations and time units
const RATE_FACTOR = BigInt(1000000000); // Factor used in yield rate calculations (10^9)
const DAY = 24 * 60 * 60; // Number of seconds in a day
const HOUR = 60 * 60; // Number of seconds in an hour

// Interface representing an action (deposit or withdraw) in the test schedule
interface ActionItem {
  day: number; // Day number relative to the start time
  hour: number; // Hour of the day
  amount: BigNumber; // Amount to deposit or withdraw
  type: "deposit" | "withdraw"; // Type of action
}

// Interface representing the yield state expected after each action
interface YieldState {
  timestampAtLastUpdate: number; // Timestamp when the state was last updated
  balanceAtLastUpdate: BigNumber; // Balance at the last update
  accruedYield: BigNumber; // Total accrued yield up to the last update
  streamYield: BigNumber; // Yield that is being streamed since the last update
}

// Interface representing a yield rate change in the contract
interface YieldRate {
  effectiveDay: number; // Day when the yield rate becomes effective
  rateValue: BigNumber; // Value of the new yield rate (expressed in RATE_FACTOR units)
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
    timestampAtLastUpdate: state.timestampAtLastUpdate,
    balanceAtLastUpdate: state.balanceAtLastUpdate,
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
  yieldStreamer: Contract,
  actionItems: ActionItem[],
  expectedYieldStates: YieldState[]
): Promise<void> {
  // Get the current block time and set the start time to the next day minus 1 second
  let currentBlockTime = Number(await time.latest());
  currentBlockTime = Math.trunc(currentBlockTime / DAY) * DAY + DAY - 1;
  const startTime = currentBlockTime;

  // Set the block timestamp to the calculated start time
  await time.setNextBlockTimestamp(currentBlockTime);

  // Iterate over each action in the schedule
  for (const [index, actionItem] of actionItems.entries()) {
    // Calculate the desired timestamp for the action based on day and hour offsets
    const desiredTimestamp = startTime + (actionItem.day - 1) * DAY + actionItem.hour * HOUR;

    // Ensure the timestamp is strictly greater than the current block timestamp
    const currentBlockTimestamp = Number(await time.latest());
    const timestampToSet = desiredTimestamp <= currentBlockTimestamp ? currentBlockTimestamp + 1 : desiredTimestamp;

    // Increase the blockchain time to the desired timestamp
    await time.increaseTo(timestampToSet);

    // Perform the deposit or withdraw action based on the action type
    if (actionItem.type === "deposit") {
      // Perform a deposit action
      await yieldStreamer.connect(user).deposit(user.address, actionItem.amount);
    } else if (actionItem.type === "withdraw") {
      // Perform a withdrawal action
      await yieldStreamer.connect(user).withdraw(user.address, actionItem.amount);
    }

    // Fetch the actual yield state from the contract after the action
    const contractYieldState = await getYieldState(yieldStreamer, user.address);

    // Update the expected timestampAtLastUpdate with the actual block timestamp
    const blockTimestamp = (await ethers.provider.getBlock("latest")).timestamp;
    expectedYieldStates[index].timestampAtLastUpdate = blockTimestamp;

    // Assert that the actual yield state matches the expected state
    expect(contractYieldState.timestampAtLastUpdate).to.equal(expectedYieldStates[index].timestampAtLastUpdate);
    expect(contractYieldState.balanceAtLastUpdate).to.equal(expectedYieldStates[index].balanceAtLastUpdate);
    expect(contractYieldState.accruedYield).to.equal(expectedYieldStates[index].accruedYield);
    expect(contractYieldState.streamYield).to.equal(expectedYieldStates[index].streamYield);
  }
}

/**
 * Adds yield rates to the contract's yield rate schedule.
 * @param yieldStreamer The YieldStreamer contract instance.
 * @param yieldRates The list of yield rates to add.
 */
async function addYieldRates(yieldStreamer: Contract, yieldRates: YieldRate[]): Promise<void> {
  const zeroBytes32 = ethers.ZeroHash; // Placeholder for the yield rate ID
  for (const yieldRate of yieldRates) {
    await yieldStreamer.addYieldRate(zeroBytes32, yieldRate.effectiveDay, yieldRate.rateValue);
  }
}

/**
 * Calculates the effective day number for a yield rate based on the current timestamp.
 * @param currentTimestamp The current blockchain timestamp.
 * @param dayNumber The day number offset from the current day.
 * @returns The effective day number for the yield rate.
 */
function calculateEffectiveDay(currentTimestamp: number, dayNumber: number): number {
  return Math.trunc((currentTimestamp + dayNumber * DAY) / DAY);
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

  // Get the signer representing the test user before the tests run
  before(async function () {
    [user] = await ethers.getSigners();
  });

  /**
   * Deploys the YieldStreamerV2 contract for testing.
   * @returns The deployed YieldStreamerV2 contract instance.
   */
  async function deployContracts(): Promise<Contract> {
    const mockToken = "0x0000000000000000000000000000000000000001";
    const YieldStreamerV2 = await ethers.getContractFactory("YieldStreamerV2");
    const yieldStreamer: Contract = await upgrades.deployProxy(YieldStreamerV2, [mockToken]);
    await yieldStreamer.waitForDeployment();
    return yieldStreamer;
  }

  describe("Function 'deposit()' and 'withdraw()'", function () {
    it("Should correctly update state for Deposit Schedule 1", async function () {
      const yieldStreamer: Contract = await setUpFixture(deployContracts);

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
          timestampAtLastUpdate: 0, // Will be updated during the test
          balanceAtLastUpdate: BigInt(1000),
          accruedYield: BigInt(0),
          streamYield: BigInt(0)
        },
        {
          // Action 2: Deposit 1000 at Day 1, 12 PM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(2000),
          accruedYield: BigInt(0),
          streamYield: BigInt(100) // Assuming yield accrual logic
        },
        {
          // Action 3, Deposit 1000 at Day 1, 6 PM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(3000),
          accruedYield: BigInt(0),
          streamYield: BigInt(300)
        },
        {
          // Action 4, Deposit 1000 at Day 2, 6 AM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(4000),
          accruedYield: BigInt(600),
          streamYield: BigInt(360)
        },
        {
          // Action 5, Deposit 1000 at Day 2, 12 PM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(5000),
          accruedYield: BigInt(600),
          streamYield: BigInt(820)
        },
        {
          // Action 6, Deposit 1000 at Day 2, 6 PM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(6000),
          accruedYield: BigInt(600),
          streamYield: BigInt(1380)
        },
        {
          // Action 7, Deposit 1000 at Day 5, 6 AM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(7000),
          accruedYield: BigInt(10934),
          streamYield: BigInt(1693)
        },
        {
          // Action 8, Deposit 1000 at Day 5, 12 PM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(8000),
          accruedYield: BigInt(10934),
          streamYield: BigInt(3486)
        },
        {
          // Action 9, Deposit 1000 at Day 5, 6 PM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(9000),
          accruedYield: BigInt(10934),
          streamYield: BigInt(5379)
        },
        {
          // Action 10, Deposit 1000 at Day 6, 6 AM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(10000),
          accruedYield: BigInt(18306),
          streamYield: BigInt(2730)
        },
        {
          // Action 11, Deposit 1000 at Day 6, 12 PM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(11000),
          accruedYield: BigInt(18306),
          streamYield: BigInt(5560)
        },
        {
          // Action 12, Deposit 1000 at Day 6, 6 PM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(12000),
          accruedYield: BigInt(18306),
          streamYield: BigInt(8490)
        }
      ];

      // Yield rates to be added to the contract
      const yieldRates: YieldRate[] = [
        { effectiveDay: 0, rateValue: RATE_FACTOR * BigInt(40) / BigInt(100) } // 40% yield rate
      ];

      // Add yield rates to the contract
      await addYieldRates(yieldStreamer, yieldRates);

      // Run the action schedule and test the yield states
      await testActionSchedule(user, yieldStreamer, actionSchedule, expectedYieldStates);
    });

    it("Should correctly update state for Deposit Schedule 2", async () => {
      const yieldStreamer: Contract = await setUpFixture(deployContracts);

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
          timestampAtLastUpdate: 0, // Will be updated during the test
          balanceAtLastUpdate: BigInt(1000),
          accruedYield: BigInt(0),
          streamYield: BigInt(0)
        },
        {
          // Action 2, Deposit 1000 at Day 1, 12 PM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(2000),
          accruedYield: BigInt(0),
          streamYield: BigInt(100)
        },
        {
          // Action 3, Deposit 1000 at Day 1, 6 PM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(3000),
          accruedYield: BigInt(0),
          streamYield: BigInt(300)
        },
        {
          // Action 4, Deposit 1000 at Day 2, 6 AM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(4000),
          accruedYield: BigInt(600),
          streamYield: BigInt(360)
        },
        {
          // Action 5, Deposit 1000 at Day 2, 12 PM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(5000),
          accruedYield: BigInt(600),
          streamYield: BigInt(820)
        },
        {
          // Action 6, Deposit 1000 at Day 2, 6 PM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(6000),
          accruedYield: BigInt(600),
          streamYield: BigInt(1380)
        },
        {
          // Action 7, Deposit 1000 at Day 5, 6 AM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(7000),
          accruedYield: BigInt(21993),
          streamYield: BigInt(2799)
        },
        {
          // Action 8, Deposit 1000 at Day 5, 12 PM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(8000),
          accruedYield: BigInt(21993),
          streamYield: BigInt(5698)
        },
        {
          // Action 9, Deposit 1000 at Day 5, 6 PM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(9000),
          accruedYield: BigInt(21993),
          streamYield: BigInt(8697)
        },
        {
          // Action 10, Deposit 1000 at Day 6, 6 AM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(10000),
          accruedYield: BigInt(33789),
          streamYield: BigInt(4278)
        },
        {
          // Action 11, Deposit 1000 at Day 6, 12 PM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(11000),
          accruedYield: BigInt(33789),
          streamYield: BigInt(8656)
        },
        {
          // Action 12, Deposit 1000 at Day 6, 6 PM
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(12000),
          accruedYield: BigInt(33789),
          streamYield: BigInt(13134)
        }
      ];

      // Yield rates to be added to the contract
      const currentBlockTime = Number(await time.latest());
      const yieldRates: YieldRate[] = [
        { effectiveDay: 0, rateValue: RATE_FACTOR * BigInt(40) / BigInt(100) }, // 40% yield rate
        { effectiveDay: calculateEffectiveDay(currentBlockTime, 3), rateValue: RATE_FACTOR * BigInt(80) / BigInt(100) }, // 80% yield rate
        { effectiveDay: calculateEffectiveDay(currentBlockTime, 5), rateValue: RATE_FACTOR * BigInt(40) / BigInt(100) } // 40% yield rate
      ];

      // Add yield rates to the contract
      await addYieldRates(yieldStreamer, yieldRates);

      // Run the action schedule and test the yield states
      await testActionSchedule(user, yieldStreamer, actionSchedule, expectedYieldStates);
    });
  });

  describe("Function 'withdraw()'", async () => {
    it("Should correctly update state for Withdraw Schedule 1", async () => {
      const yieldStreamer: Contract = await setUpFixture(deployContracts);

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
          timestampAtLastUpdate: 0, // Will be updated during the test
          balanceAtLastUpdate: BigInt(11000),
          accruedYield: BigInt(0),
          streamYield: BigInt(0)
        },
        {
          // Action 2, Day 1, 12 PM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(10000),
          accruedYield: BigInt(0),
          streamYield: BigInt(1100)
        },
        {
          // Action 3, Day 1, 6 PM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(9000),
          accruedYield: BigInt(0),
          streamYield: BigInt(2100)
        },
        {
          // Action 4, Day 2, 6 AM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(8000),
          accruedYield: BigInt(3000),
          streamYield: BigInt(1200)
        },
        {
          // Action 5, Day 2, 12 PM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(7000),
          accruedYield: BigInt(3000),
          streamYield: BigInt(2300)
        },
        {
          // Action 6, Day 2, 6 PM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(6000),
          accruedYield: BigInt(3000),
          streamYield: BigInt(3300)
        },
        {
          // Action 7, Day 5, 6 AM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(5000),
          accruedYield: BigInt(19872),
          streamYield: BigInt(2587)
        },
        {
          // Action 8, Day 5, 12 PM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(4000),
          accruedYield: BigInt(19872),
          streamYield: BigInt(5074)
        },
        {
          // Action 9, Day 5, 6 PM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(3000),
          accruedYield: BigInt(19872),
          streamYield: BigInt(7461)
        },
        {
          // Action 10, Day 6, 6 AM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(2000),
          accruedYield: BigInt(29620),
          streamYield: BigInt(3262)
        },
        {
          // Action 11, Day 6, 12 PM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(1000),
          accruedYield: BigInt(29620),
          streamYield: BigInt(6424)
        },
        {
          // Action 12, Day 6, 6 PM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(0),
          accruedYield: BigInt(29620),
          streamYield: BigInt(9486)
        }
      ];

      // Yield rates to be added to the contract
      const yieldRates: YieldRate[] = [
        { effectiveDay: 0, rateValue: RATE_FACTOR * BigInt(40) / BigInt(100) } // 40% yield rate
      ];

      // Add yield rates to the contract
      await addYieldRates(yieldStreamer, yieldRates);

      // Run the action schedule and test the yield states
      await testActionSchedule(user, yieldStreamer, actionSchedule, expectedYieldStates);
    });

    it("Should correctly update state for Withdraw Schedule 2", async () => {
      const yieldStreamer: Contract = await setUpFixture(deployContracts);

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
          timestampAtLastUpdate: 0, // Will be updated during the test
          balanceAtLastUpdate: BigInt(11000),
          accruedYield: BigInt(0),
          streamYield: BigInt(0)
        },
        {
          // Action 2, Day 1, 12 PM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(10000),
          accruedYield: BigInt(0),
          streamYield: BigInt(1100)
        },
        {
          // Action 3, Day 1, 6 PM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(9000),
          accruedYield: BigInt(0),
          streamYield: BigInt(2100)
        },
        {
          // Action 4, Day 2, 6 AM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(8000),
          accruedYield: BigInt(3000),
          streamYield: BigInt(1200)
        },
        {
          // Action 5, Day 2, 12 PM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(7000),
          accruedYield: BigInt(3000),
          streamYield: BigInt(2300)
        },
        {
          // Action 6, Day 2, 6 PM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(6000),
          accruedYield: BigInt(3000),
          streamYield: BigInt(3300)
        },
        {
          // Action 7, Day 5, 6 AM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(5000),
          accruedYield: BigInt(36768),
          streamYield: BigInt(4276)
        },
        {
          // Action 8, Day 5, 12 PM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(4000),
          accruedYield: BigInt(36768),
          streamYield: BigInt(8452)
        },
        {
          // Action 9, Day 5, 6 PM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(3000),
          accruedYield: BigInt(36768),
          streamYield: BigInt(12528)
        },
        {
          // Action 10, Day 6, 6 AM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(2000),
          accruedYield: BigInt(53272),
          streamYield: BigInt(5627)
        },
        {
          // Action 11, Day 6, 12 PM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(1000),
          accruedYield: BigInt(53272),
          streamYield: BigInt(11154)
        },
        {
          // Action 12, Day 6, 6 PM, Withdraw 1000
          timestampAtLastUpdate: 0,
          balanceAtLastUpdate: BigInt(0),
          accruedYield: BigInt(53272),
          streamYield: BigInt(16581)
        }
      ];

      // Yield rates to be added to the contract
      const currentBlockTime = Number(await time.latest());
      const yieldRates: YieldRate[] = [
        { effectiveDay: 0, rateValue: RATE_FACTOR * BigInt(40) / BigInt(100) }, // 40% yield rate
        { effectiveDay: calculateEffectiveDay(currentBlockTime, 3), rateValue: RATE_FACTOR * BigInt(80) / BigInt(100) }, // 80% yield rate
        { effectiveDay: calculateEffectiveDay(currentBlockTime, 5), rateValue: RATE_FACTOR * BigInt(40) / BigInt(100) } // 40% yield rate
      ];

      // Add yield rates to the contract
      await addYieldRates(yieldStreamer, yieldRates);

      // Run the action schedule and test the yield states
      await testActionSchedule(user, yieldStreamer, actionSchedule, expectedYieldStates);
    });
  });
});
