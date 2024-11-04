const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ServiceHub", function () {
  let serviceHub, token, priceFeed, owner, provider, subscriber;

  before(async function () {
    // Use DAI as the ERC20 token and Chainlink's ETH/USD price feed
    const daiAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
    const ethUsdPriceFeedAddress = "0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9";
    const dai_whale = "0xc08a8a9f809107c5A7Be6d90e315e4012c99F39a";
  
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [dai_whale],
    });

    [owner, provider] = await ethers.getSigners();
    subscriber = await ethers.getSigner(dai_whale);

    // Attach to the DAI token and Chainlink price feed on mainnet
    token = await ethers.getContractAt("IERC20", daiAddress);
    priceFeed = await ethers.getContractAt("AggregatorV3Interface", ethUsdPriceFeedAddress);

    // Deploy ServiceHub contract
    const ServiceHub = await ethers.getContractFactory("ServiceHub");
    serviceHub = await ServiceHub.deploy();
    await serviceHub.initialize(token.target, priceFeed.target);
  });

  it("should register a provider with the minimum required fee", async function () {
    const providerId = 1;
    const monthlyFee = ethers.parseUnits("55", 18); // Monthly fee in DAI

    // Register the provider
    await expect(
      serviceHub.connect(provider).registerProvider(providerId, monthlyFee)
    ).to.emit(serviceHub, "ProviderRegistered").withArgs(providerId, provider.address, monthlyFee);

    // Check provider state
    const providerState = await serviceHub.getProviderState(providerId);
    expect(providerState.owner).to.equal(provider.address);
    expect(providerState.feePerSecond).to.be.gt(0); // Check per-second fee calculation
    expect(providerState.isActive).to.be.true;
  });

  it("should prevent registering a provider with a fee below the minimum", async function () {
    const providerId = 2;
    const insufficientFee = ethers.parseUnits("25", 18); // $25, below the minimum $50

    await expect(
      serviceHub.connect(provider).registerProvider(providerId, insufficientFee)
    ).to.be.revertedWith("Fee below minimum required");
  });

  it("should register a subscriber with a minimum deposit", async function () {
    const subscriberId = 1;
    const deposit = ethers.parseUnits("101", 18); // $100 deposit in DAI
    const providerId = 1;

    // Approve and deposit DAI from subscriber
    await token.connect(subscriber).approve(serviceHub.target, deposit);
    await expect(
      serviceHub.connect(subscriber).subscribe(subscriberId, providerId, deposit)
    ).to.emit(serviceHub, "SubscriberRegistered").withArgs(subscriberId, subscriber.address, deposit);

    // Check subscriber state
    const subscriberState = await serviceHub.getSubscriberState(subscriberId);
    expect(await serviceHub.checkSubscriptionStatus(1, 1)).to.be.equal(true)
    expect(subscriberState.owner).to.equal(subscriber.address);
    expect(subscriberState.balance).to.be.gt(0);
    // console.log(await serviceHub.getSubscriberState(1))
  });

  it("should allow a provider to withdraw earnings", async function () {
    const providerId = 1;

    // Withdraw earnings
    const providerBalanceBefore = await token.balanceOf(provider.address);
    await expect(serviceHub.connect(provider).withdrawEarnings(providerId))
      .to.emit(serviceHub, "EarningsWithdrawn");

    // Check provider balance
    const providerBalanceAfter = await token.balanceOf(provider.address);
    expect(providerBalanceAfter).to.be.gt(providerBalanceBefore);
  });

  it("should increase subscription deposit for a subscriber", async function () {
    const subscriberId = 1;
    const providerId = 1;
    const additionalDeposit = ethers.parseUnits("50", 18); // Additional $50

    await token.connect(subscriber).approve(serviceHub.target, additionalDeposit);
    await expect(serviceHub.connect(subscriber).increaseSubscriptionDeposit(subscriberId, providerId, additionalDeposit))
      .to.emit(serviceHub, "SubscriptionIncreased")
      .withArgs(subscriberId, additionalDeposit);

    const updatedSubscriberState = await serviceHub.getSubscriberBalance(subscriberId);
    expect(updatedSubscriberState).to.be.gt(ethers.parseUnits("100", 18)); // Initial $100 + $50
  });

  it("should increase provider fee", async function () {
    const providerId = 1;
    // New monthly fee to increase
    const newMonthlyFee = ethers.parseEther("100");

    // Increase provider fee
    await serviceHub.connect(provider).setProviderFee(providerId, newMonthlyFee);

    // Check updated fee
    const updatedProvider = await serviceHub.getProviderState(providerId);
    expect(updatedProvider.feePerSecond).to.equal(newMonthlyFee / BigInt(30 * 24 * 60 * 60));
});

  it("should update provider state by the owner", async function () {
    const providerId = 1;
    await expect(serviceHub.connect(owner).updateProviderState(providerId, false))
      .to.emit(serviceHub, "ProviderStateUpdated")
      .withArgs(providerId, false);

    const providerState = await serviceHub.getProviderState(providerId);
    expect(providerState.isActive).to.be.false;
  });
});
