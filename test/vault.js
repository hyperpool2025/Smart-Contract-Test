const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("USDCVault with MockAAVE", function () {
  let usdc, mockAAVE, vault, aToken;
  let owner, user, treasury, other;

  beforeEach(async () => {
    [owner, user, treasury, other] = await ethers.getSigners();

    // Deploy MockUSDC
    const MockUSDC = await ethers.getContractFactory("MockUSDC");
    usdc = await MockUSDC.deploy();
    await usdc.waitForDeployment();

    // Mint USDC for users
    await usdc.mint(user.address, ethers.parseUnits("1000", 6));
    await usdc.mint(other.address, ethers.parseUnits("1000", 6));

    // Deploy MockAAVE
    const MockAAVE = await ethers.getContractFactory("MockAAVE");
    mockAAVE = await MockAAVE.deploy(await usdc.getAddress());
    await mockAAVE.waitForDeployment();

    // Get aToken address
    const aTokenAddress = await mockAAVE.aToken();
    aToken = await ethers.getContractAt("MockAToken", aTokenAddress);

    // Deploy Vault
    const Vault = await ethers.getContractFactory("USDCVault");
    vault = await Vault.deploy(await usdc.getAddress(), treasury.address, await mockAAVE.getAddress());
    await vault.waitForDeployment();
    owner=vault.owner();
    console.log(vault.owner())
  });

  it("user can deposit and get shares, vault gets aTokens", async () => {
    const amount = ethers.parseUnits("500", 6);
    await usdc.connect(user).approve(await vault.getAddress(), amount);

    await expect(vault.connect(user).deposit(amount, user.address))
      .to.emit(vault, "Deposit")
      .withArgs(user.address, user.address, amount, amount);

    expect(await vault.balanceOf(user.address)).to.eq(amount);
    expect(await aToken.balanceOf(await vault.getAddress())).to.eq(amount);
    expect(await vault.getInitialDeposit(user.address)).to.eq(amount);
  });

  it("user can withdraw partial funds, vault burns aTokens", async () => {
    const amount = ethers.parseUnits("500", 6);
    await usdc.connect(user).approve(await vault.getAddress(), amount);
    await vault.connect(user).deposit(amount, user.address);

    const half = ethers.parseUnits("150", 6);
    const rest = ethers.parseUnits("350", 6);
    await vault.connect(user).withdraw(half, user.address, user.address);

    expect(await usdc.balanceOf(user.address)).to.be.closeTo(
      ethers.parseUnits("650", 6),
      ethers.parseUnits("1", 2)
    );
    expect(await vault.getInitialDeposit(user.address)).to.eq(rest);
    expect(await vault.balanceOf(user.address)).to.eq(rest);
    expect(await aToken.balanceOf(await vault.getAddress())).to.eq(rest);
  });

  it("treasury can restake to another protocol", async () => {
    const amount = ethers.parseUnits("500", 6);
    await usdc.connect(user).approve(await vault.getAddress(), amount);
    await vault.connect(user).deposit(amount, user.address);

    // Deploy another MockAAVE
    const MockAAVE2 = await ethers.getContractFactory("MockAAVE");
    const mockAAVE2 = await MockAAVE2.deploy(await usdc.getAddress());
    await mockAAVE2.waitForDeployment();
    const balance = await ethers.provider.getBalance(treasury.address);
    console.log("Matic Balance:", ethers.formatEther(balance));

    await expect(vault.connect(treasury).restake(await mockAAVE2.getAddress()))
      .to.emit(vault, "ProtocolRestaked");

    expect(await vault.currentProtocol()).to.eq(await mockAAVE2.getAddress());
    // All aTokens in new protocol (simulate by checking aToken balance in new protocol)
    const aToken2 = await ethers.getContractAt("MockAToken", await mockAAVE2.aToken());
    expect(await aToken2.balanceOf(await vault.getAddress())).to.eq(amount);
  });

  it("getAvailableBalance and profit after interest", async () => {
    const amount = ethers.parseUnits("500", 6);
    await usdc.connect(user).approve(await vault.getAddress(), amount);
    await vault.connect(user).deposit(amount, user.address);

    // Simulate profit: mint extra aTokens to vault (like AAVE interest)
    // Only minter (MockAAVE) can mint, so call via MockAAVE
    await mockAAVE.aToken(); // just to ensure aToken is deployed

    // Simulate profit: mint extra aTokens to vault (like AAVE interest) . This is only for test purpose
    await mockAAVE.mintYield(await vault.getAddress(), ethers.parseUnits("50", 6));

    const bal = await vault.getAvailableBalance(user.address);
    // User's full share = 550, profit = 50, fee = 2.5, payout = 547.5
    expect(bal).to.equal(ethers.parseUnits("547.5", 6));
  });

 
});