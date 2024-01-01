const { ethers, upgrades } = require("hardhat");

async function main() {
  const CONTRACT_NAME = ""; // TODO: Enter contract name
  const factory = await ethers.getContractFactory(CONTRACT_NAME);
  const proxy = await upgrades.deployProxy(factory);
  await proxy.waitForDeployment();
  console.log("Proxy deployed to:", await proxy.getAddress());
}

main();
