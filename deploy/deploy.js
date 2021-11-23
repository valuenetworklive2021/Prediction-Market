const fs = require("fs");

const { getNamedAccounts, getChainId, deployments, run } = require("hardhat");
const { deploy } = deployments;

const ethUsdOracle = "0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada";
const operatorAddress = "0x024D3242650d6c7b0ee6DE408E33E803dbfb00Ea";

async function main() {
  const namedAccounts = await getNamedAccounts();
  const { deployer } = namedAccounts;

  const chainId = await getChainId();

  const predictionMarket = await deployAndVerify(
    "PredictionMarket",
    [ethUsdOracle, operatorAddress],
    deployer,
    "contracts/PredictionMarket.sol:PredictionMarket",
    chainId
  );

  console.log("PredictionMarket deployed to:", predictionMarket.address);
  await store(predictionMarket.address, chainId);
}

const deployAndVerify = async (
  contractName,
  args,
  deployer,
  contractPath,
  chainId
) => {
  const contractInstance = await deploy(contractName, {
    from: deployer,
    args,
    log: true,
    deterministicDeployment: false,
  });

  console.log(`${contractName} deployed: ${contractInstance.address}`);
  console.log("verifying the contract:");

  try {
    if (parseInt(chainId) !== 31337) {
      await sleep(30);
      await run("verify:verify", {
        address: contractInstance.address,
        contract: contractPath,
        constructorArguments: args,
      });
    }
  } catch (error) {
    console.log("Error during verification", error);
  }

  return contractInstance;
};

const store = async (data, chainId) => {
  fs.writeFileSync(
    __dirname + `/../${chainId}-addresses.json`,
    JSON.stringify(data)
  );
};

const sleep = (delay) =>
  new Promise((resolve) => setTimeout(resolve, delay * 1000));

module.exports = main;
