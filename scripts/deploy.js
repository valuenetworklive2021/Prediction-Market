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
