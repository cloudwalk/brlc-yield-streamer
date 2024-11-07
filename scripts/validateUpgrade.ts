import { ethers, upgrades } from "hardhat";

async function main() {
  const CONTRACT_NAME: string = "YieldStreamerV2"; // TODO: Enter contract name
  const PROXY_ADDRESS: string = "0x9d4454B023096f34B160D6B654540c56A1F81688"; // TODO: Enter proxy address

  // Upgrade options:
  // - unsafeAllowRenames: true
  // - unsafeSkipStorageCheck: true

  const factory = await ethers.getContractFactory(CONTRACT_NAME);
  await upgrades.validateUpgrade(PROXY_ADDRESS, factory);

  console.log("Successfully validated");
}

main().then().catch(err => {
  throw err;
});
