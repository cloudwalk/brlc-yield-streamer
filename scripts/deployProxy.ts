import { ethers, upgrades } from "hardhat";

async function main() {
  const CONTRACT_NAME: string = "YieldStreamerV2"; // TODO: Enter contract name
  const TOKEN_ADDRESS: string = "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"; // TODO: Enter token contract address

  const factory = await ethers.getContractFactory(CONTRACT_NAME);
  const proxy = await upgrades.deployProxy(
    factory,
    [TOKEN_ADDRESS],
    { kind: "uups" }
  );

  await proxy.waitForDeployment();

  console.log("Proxy deployed to:", await proxy.getAddress());
}

main().then().catch(err => {
  throw err;
});
