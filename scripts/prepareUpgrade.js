const { ethers, upgrades } = require("hardhat");

async function main() {
  const CONTRACT_NAME = ""; // TODO: Enter contract name
  const PROXY_ADDRESS = ""; // TODO: Enter proxy address

  // Upgrade options
  // unsafeAllowRenames: true
  // unsafeSkipStorageCheck: true

  const factory = await ethers.getContractFactory(CONTRACT_NAME);
  await upgrades.prepareUpgrade(PROXY_ADDRESS, factory);
  console.log("Upgrade prepared");
}

main();
