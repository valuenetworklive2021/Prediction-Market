const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("PredictionMarket", function () {
  it("works", async () => {
    const PredictionMarket = await ethers.getContractFactory(
      "PredictionMarket"
    );
    const PredictionMarketV2 = await ethers.getContractFactory(
      "PredictionMarket"
    );

    const instance = await upgrades.deployProxy(PredictionMarket, [
      "0x0000000000000000000000000000000000000001",
    ]);

    const upgraded = await upgrades.upgradeProxy(
      instance.address,
      PredictionMarketV2
    );

    const latestConditionIndex = await upgraded.latestConditionIndex();
    expect(latestConditionIndex.toString()).to.equal("0");
  });
});
