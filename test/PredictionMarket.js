const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("PredictionMarket", function () {
  it("deploys", async () => {
    const PredictionMarket = await ethers.getContractFactory(
      "PredictionMarket"
    );

    const predictionMarket = await PredictionMarket.deploy(
      "0x0000000000000000000000000000000000000001",
      "0x0000000000000000000000000000000000000001"
    );

    const latestConditionIndex = await predictionMarket.latestConditionIndex();
    expect(latestConditionIndex.toString()).to.equal("0");
  });
});
