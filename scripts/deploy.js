const { ethers, run } = require("hardhat");

async function main() {
  await run("compile");

  // We get the contract
  const PredictionMarket = await ethers.getContractFactory("PredictionMarket");
  const ethUsdOracle = "";
  const operatorAddress = "";

  // deploy contracts
  const predictionMarket = await PredictionMarket.deploy(
    ethUsdOracle,
    operatorAddress
  );

  await predictionMarket.deployed();
  console.log("PredictionMarket deployed to:", predictionMarket.address);

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
