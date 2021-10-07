const { ethers, upgrades, run } = require("hardhat");

async function main() {
  await run("compile");

  // We get the contract to deploy
  const PredictionMarket = await ethers.getContractFactory("PredictionMarket");
  const predictionMarket = await upgrades.deployProxy(PredictionMarket, [""]);
  await predictionMarket.deployed();
  console.log("PredictionMarket deployed to:", predictionMarket.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

/**
 * TO VERIFY CONTRACT
 1. hardhat run --network networkName scripts/deploy.js

 * Then, copy the deployment address and paste it in to replace `DEPLOYED_CONTRACT_ADDRESS` in this command:
 2. npx hardhat verify --network networkName DEPLOYED_CONTRACT_ADDRESS
 
 */
