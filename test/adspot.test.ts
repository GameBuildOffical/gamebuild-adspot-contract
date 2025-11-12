import { expect } from "chai";
import { ethers } from "hardhat";

describe("AdSpot Protocol", function () {
  it("mints, lists, buys, rents, and claims", async function () {
    const [deployer, seller, buyer, renter, fee] = await ethers.getSigners();

    const NFT = await ethers.getContractFactory("AdSpotNFT");
    const nft = await NFT.connect(deployer).deploy(deployer.address);
    await nft.waitForDeployment();

    const Market = await ethers.getContractFactory("AdSpotMarket");
    const market = await Market.connect(deployer).deploy(deployer.address, await fee.getAddress(), 250);
    await market.waitForDeployment();

    // create a spot and send to seller
    await (await nft.createSpot("ipfs://spot1")).wait();
    await (await nft.transferFrom(await deployer.getAddress(), await seller.getAddress(), 1)).wait();

    // seller lists
    await (await nft.connect(seller).approve(await market.getAddress(), 1)).wait();
    await (await market.connect(seller).list(await nft.getAddress(), 1, ethers.parseEther("1"))).wait();

    // buyer purchases
    await (await market.connect(buyer).buy(await nft.getAddress(), 1, { value: ethers.parseEther("1") })).wait();

    // claim shares
    const feeBefore = await market.claimable(await fee.getAddress());
    expect(feeBefore).to.equal(ethers.parseEther("0.025"));

    // buyer sets rental price
    await (await nft.connect(buyer).setPricePerSecond(1, ethers.parseEther("0.000001"))).wait();

    // renter pays rent via market (to split fees), then calls rent on NFT
    await (await market.connect(renter).payRent(await nft.getAddress(), 1, { value: ethers.parseEther("0.0036") })).wait();
    await (await nft.connect(renter).rent(1, 3600)).wait();
    const user = await nft.userOf(1);
    expect(user).to.equal(await renter.getAddress());

    // seller claims proceeds; should be 0.975 (buyer purchase) credited to seller + none from rent (credited to buyer-owner)
    const sellerClaim = await market.claimable(await seller.getAddress());
    expect(sellerClaim).to.equal(ethers.parseEther("0.975"));

    // buyer-owner got rent less fee (0.0036 - 2.5% = 0.00351)
    const buyerClaim = await market.claimable(await buyer.getAddress());
    expect(buyerClaim).to.equal(ethers.parseEther("0.00351"));
  });
});
