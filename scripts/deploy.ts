import { ethers } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with", deployer.address);

  const AdSpotNFT = await ethers.getContractFactory("AdSpotNFT");
  const nft = await AdSpotNFT.deploy(deployer.address);
  await nft.waitForDeployment();
  console.log("AdSpotNFT deployed at", await nft.getAddress());

  const AdSpotMarket = await ethers.getContractFactory("AdSpotMarket");
  const market = await AdSpotMarket.deploy(deployer.address, deployer.address, 250); // 2.5% fee
  await market.waitForDeployment();
  console.log("AdSpotMarket deployed at", await market.getAddress());

  // Example initial spot
  const tx = await nft.createSpot("ipfs://example-adspot-metadata");
  await tx.wait();
  console.log("Initial ad spot minted tokenId=1");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
