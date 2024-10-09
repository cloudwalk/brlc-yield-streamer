import { ethers, network } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";
import { BlockTag, TransactionReceipt, TransactionResponse } from "@ethersproject/abstract-provider";

export async function getBlockTimestamp(blockTag: BlockTag): Promise<number> {
  const block = await ethers.provider.getBlock(blockTag);
  return block?.timestamp ?? 0;
}

export async function getLatestBlockTimestamp(): Promise<number> {
  return getBlockTimestamp("latest");
}

export async function increaseBlockTimestampTo(targetTimestamp: number) {
  if (network.name === "hardhat") {
    await time.increaseTo(targetTimestamp);
  } else if (network.name === "stratus") {
    await ethers.provider.send("evm_setNextBlockTimestamp", [targetTimestamp]);
    await ethers.provider.send("evm_mine", []);
  } else {
    throw new Error(`Setting block timestamp for the current blockchain is not supported: ${network.name}`);
  }
}

export async function increaseBlockTimestamp(increaseInSeconds: number) {
  if (increaseInSeconds <= 0) {
    throw new Error(`The block timestamp increase must be greater than zero, but it equals: ${increaseInSeconds}`);
  }
  const currentTimestamp = await getLatestBlockTimestamp();
  await increaseBlockTimestampTo(currentTimestamp + increaseInSeconds);
}

export async function proveTx(txResponsePromise: Promise<TransactionResponse>): Promise<TransactionReceipt> {
  const txReceipt = await txResponsePromise;
  return txReceipt.wait();
}
