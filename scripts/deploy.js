const { ethers, upgrades, run } = require("hardhat");

async function main() {
  await run("compile");

  // We get the contract
  const PredictionMarket = await ethers.getContractFactory("PredictionMarket");

  // *********** to deploy ***********
  const predictionMarket = await upgrades.deployProxy(PredictionMarket, [
    "0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526",
  ]);
  await predictionMarket.deployed();
  console.log("PredictionMarket proxy deployed to:", predictionMarket.address);

  const predictionMarketImplAddress =
    await predictionMarket.getProxyImplementation();

  console.log(
    "PredictionMarket implementation deployed to:",
    predictionMarketImplAddress
  );

  // *********** to upgrade ***********
  // const predictionMarket = await upgrades.upgradeProxy(
  //   proxyAddress,
  //   PredictionMarket
  // );

  // console.log("PredictionMarket upgraded");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

/**
 * TO VERIFY CONTRACT
 1. hardhat run --network networkName scripts/deploy.js
 ** had to initialise manually, do check

 * Then, copy the deployment address and paste it in to replace `DEPLOYED_CONTRACT_ADDRESS` in this command:
 2. npx hardhat verify --network networkName DEPLOYED_CONTRACT_ADDRESS
 
 */
