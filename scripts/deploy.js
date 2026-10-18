const hre = require("hardhat");
async function main() {
  const Insurance = await hre.ethers.getContractFactory("OmniParametricInsurance");
  const insurance = await Insurance.deploy();
  await insurance.deployed();
  console.log("Insurance Hub deployed to:", insurance.address);
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
