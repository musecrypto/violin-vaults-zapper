const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");

const quickswap = "0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32";
const ZERO_ADDR = "0x0000000000000000000000000000000000000000";
const ONE_ADDR = "0x0000000000000000000000000000000000000001";

const ONE = ethers.utils.parseEther("1");

describe("Zap testing", function () {
  var Zap;
  let ZapHandlerV1;
  let UniFactory;
  let UniPair;
  let Token0;
  let Token1;
  

  before("Should deploy contracts", async function () {
    [owner, wallet1, walletTo] = await ethers.getSigners();
    // mint  matic
    await network.provider.send("hardhat_setBalance", [
      owner.address,
      '0xde0b6b3a7640000'
    ]);
    await network.provider.send("hardhat_setBalance", [
      wallet1.address,
      '0xde0b6b3a7640000'
    ]);
    const uniFactoryFactory = await ethers.getContractFactory("MockFactory");
    UniFactory = await uniFactoryFactory.attach(quickswap);

    const ZapFactory = await ethers.getContractFactory("Zap");
    const ZapHandlerV1Factory = await ethers.getContractFactory("ZapHandlerV1", owner);
    const TestTokenFactory = await ethers.getContractFactory("TestToken", owner);
    Zap = await ZapFactory.deploy();
    ZapHandlerV1 = await ZapHandlerV1Factory.deploy();
    Token0 = await TestTokenFactory.deploy("TestToken1", "TST");
    Token1 = await TestTokenFactory.deploy("TestToken2", "TST");
    await UniFactory.connect(owner).createPair(Token0.address, Token1.address);
    const pair = await UniFactory.getPair(Token0.address, Token1.address);

    const uniPairFactory = await ethers.getContractFactory("MockPair", owner);
    UniPair = await uniPairFactory.attach(pair);
    await Token0.connect(owner).mint(ethers.utils.parseEther("1000"));
    await Token1.connect(owner).mint(ethers.utils.parseEther("1000"));
    await Token0.connect(owner).transfer(UniPair.address, ethers.utils.parseEther("100"));
    await Token1.connect(owner).transfer(UniPair.address, ethers.utils.parseEther("200"));
    await UniPair.connect(owner).mint(owner.address);
  });

  it("It should revert pullTo from wallet", async function () {
    await expect(Zap.connect(owner).pullTo(owner.address))
      .to.be.revertedWith("!implementation");
    await expect(Zap.connect(owner).pullAmountTo(owner.address, 100))
      .to.be.revertedWith("!implementation");
  });


  it("It should revert setImplementation from non-owner", async function () {
    await expect(Zap.connect(wallet1).setImplementation(ZapHandlerV1.address))
      .to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("It should allow setImplementation from owner", async function () {
    expect(await Zap.implementation()).to.be.equal(ZERO_ADDR);
    await expect(Zap.connect(owner).setImplementation(ZapHandlerV1.address))
      .to.emit(Zap, "ImplementationChanged")
      .withArgs(ZERO_ADDR, ZapHandlerV1.address);
    expect(await Zap.implementation()).to.be.equal(ZapHandlerV1.address);
  });

  it("It should revert zapping without a route", async function () {
    await expect(Zap.connect(owner).zapERC20(Token0.address, Token1.address, 100, 0))
      .to.be.revertedWith("Route length zero, TODO: generate new route automatically");
  });

  it("It should not allow governance functions by non-owner", async function () {
    await expect(ZapHandlerV1.connect(wallet1).setFactory(quickswap, 0, 0))
      .to.be.revertedWith("Ownable: caller is not the owner");
    await expect(ZapHandlerV1.connect(wallet1).removeFactory(quickswap))
      .to.be.revertedWith("Ownable: caller is not the owner");
    await expect(ZapHandlerV1.connect(wallet1).setRoute(Token0.address, Token1.address, [Token0.address, quickswap, Token1.address]))
      .to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("It should not allow adding a route while the router is not addded", async function () {
    await expect(ZapHandlerV1.connect(owner).setRoute(Token0.address, Token1.address, [Token0.address, quickswap, Token1.address]))
      .to.be.revertedWith("!factory does not exist");
  });
  it("It should not allow adding the zero factory", async function () {
    await expect(ZapHandlerV1.connect(owner).setFactory(ZERO_ADDR, 997, 1000))
      .to.be.revertedWith("!zero factory");
  });
  it("It should not allow zero nom or denom when adding factory", async function () {
    await expect(ZapHandlerV1.connect(owner).setFactory(ZERO_ADDR, 0, 1000))
      .to.be.revertedWith("!zero");
    await expect(ZapHandlerV1.connect(owner).setFactory(ZERO_ADDR, 0, 0))
      .to.be.revertedWith("!zero");
  });
  it("It should not allow nom>denom when adding factory", async function () {
    await expect(ZapHandlerV1.connect(owner).setFactory(ZERO_ADDR, 1001, 1000))
      .to.be.revertedWith("!nom > denom");
  });

  it("It should allow adding quickswap", async function () {
    await expect(ZapHandlerV1.connect(owner).setFactory(quickswap, 998, 1000))
      .to.emit(ZapHandlerV1, "FactorySet")
      .withArgs(quickswap, false, 998, 1000);
    expect(await (ZapHandlerV1.factoryLength())).to.be.equal(1);
    expect(await (ZapHandlerV1.getFactory(0))).to.be.equal(quickswap);
    const factory = await (ZapHandlerV1.factories(quickswap));
    expect(factory[0]).to.be.equal(quickswap);
    expect(factory[1]).to.be.equal(998);
    expect(factory[2]).to.be.equal(1000);
  });

  it("It should allow updating quickswap", async function () {
    await expect(ZapHandlerV1.connect(owner).setFactory(quickswap, 997, 1000))
      .to.emit(ZapHandlerV1, "FactorySet")
      .withArgs(quickswap, true, 997, 1000);
    expect(await (ZapHandlerV1.factoryLength())).to.be.equal(1);
    expect(await (ZapHandlerV1.getFactory(0))).to.be.equal(quickswap);
    const factory = await (ZapHandlerV1.factories(quickswap));
    expect(factory[0]).to.be.equal(quickswap);
    expect(factory[1]).to.be.equal(997);
    expect(factory[2]).to.be.equal(1000);
  });

  it("It should allow adding a route", async function () {
    await expect(ZapHandlerV1.connect(owner).setRoute(Token0.address, Token1.address, [Token0.address, quickswap, Token1.address]))
      .to.emit(ZapHandlerV1, "RouteAdded")
      .withArgs(Token0.address, Token1.address, false);
    await expect(ZapHandlerV1.connect(owner).setRoute(Token0.address, Token1.address, [Token0.address, quickswap, Token1.address]))
      .to.emit(ZapHandlerV1, "RouteAdded")
      .withArgs(Token1.address, Token0.address, true);
    
    const routeStep= await (ZapHandlerV1.routes(Token0.address, Token1.address, 0));
    expect(await ZapHandlerV1.routeLength(Token0.address, Token1.address)).to.be.equal(1);
    expect(routeStep[0]).to.be.equal(Token0.address);
    expect(routeStep[1]).to.be.equal(Token1.address);
    expect(routeStep[2]).to.be.equal(UniPair.address);
    expect(routeStep[3]).to.be.equal(997);
    expect(routeStep[4]).to.be.equal(1000);
  });


  it("It should revert zapping while unapproved", async function () {
    await expect(Zap.connect(owner).zapERC20(Token0.address, Token1.address, 100, 0))
    .to.be.revertedWith("ERC20: transfer amount exceeds allowance");
  });

  it("It should allow zapping from token0 to token1 once approved", async function () {
    expect(await Zap.from()).to.equal(ONE_ADDR);
    const expected = BigNumber.from("1974316068794122597");
    await Token0.transfer(wallet1.address, ONE.mul(BigNumber.from(2)));
    await Token0.connect(wallet1).approve(Zap.address, ONE.mul(BigNumber.from(2)));
    const bal0Before = await Token0.balanceOf(wallet1.address);
    const bal1Before = await Token1.balanceOf(wallet1.address);

    await Zap.connect(wallet1).zapERC20(Token0.address, Token1.address, ONE, 0);


    const bal0After = await Token0.balanceOf(wallet1.address);
    const bal1After = await Token1.balanceOf(wallet1.address);
    
    expect(bal0Before.sub(bal0After)).to.be.equal(ONE);
    expect(bal1After.sub(bal1Before)).to.be.equal(expected);

    expect(await Zap.from()).to.equal(ONE_ADDR);
  });
  it("It should allow zapping from token0 to token1 once more", async function () {
    expect(await Zap.from()).to.equal(ONE_ADDR);
    const expected = BigNumber.from("1935660920217381489");
    const bal0Before = await Token0.balanceOf(wallet1.address);
    const bal1Before = await Token1.balanceOf(wallet1.address);

    const tx = await Zap.connect(wallet1).zapERC20(Token0.address, Token1.address, ONE, 0);
    const receipt = await tx.wait();

    const bal0After = await Token0.balanceOf(wallet1.address);
    const bal1After = await Token1.balanceOf(wallet1.address);
    
    expect(bal0Before.sub(bal0After)).to.be.equal(ONE);
    expect(bal1After.sub(bal1Before)).to.be.equal(expected);

    expect(await Zap.from()).to.equal(ONE_ADDR);
    
    expect(receipt.gasUsed).to.eq(118557);
  });


  it("It should allow zapping from pair to token1", async function () {
    expect(await Zap.from()).to.equal(ONE_ADDR);
    const expected = BigNumber.from("2759212488640045545");
    const bal0Before = await UniPair.balanceOf(owner.address);
    const bal1Before = await Token1.balanceOf(owner.address);
    UniPair.approve(Zap.address, ONE.mul(BigNumber.from(2)));
    await Zap.connect(owner).zapERC20(UniPair.address, Token1.address, ONE, 0);

    const bal0After = await UniPair.balanceOf(owner.address);
    const bal1After = await Token1.balanceOf(owner.address);
    
    expect(bal0Before.sub(bal0After)).to.be.equal(ONE);
    expect(bal1After.sub(bal1Before)).to.be.equal(expected);

    expect(await Zap.from()).to.equal(ONE_ADDR);
  });

  it("It should allow zapping from pair to token1 once more", async function () {
    expect(await Zap.from()).to.equal(ONE_ADDR);
    const expected = BigNumber.from("2739686382709045481");
    const bal0Before = await UniPair.balanceOf(owner.address);
    const bal1Before = await Token1.balanceOf(owner.address);
    const tx = await Zap.connect(owner).zapERC20(UniPair.address, Token1.address, ONE, 0);
    const receipt = await tx.wait();

    const bal0After = await UniPair.balanceOf(owner.address);
    const bal1After = await Token1.balanceOf(owner.address);
    
    expect(bal0Before.sub(bal0After)).to.be.equal(ONE);
    expect(bal1After.sub(bal1Before)).to.be.equal(expected);

    expect(await Zap.from()).to.equal(ONE_ADDR);
    
    expect(receipt.gasUsed).to.eq(226443);
  });

  it("It should allow zapping from token1 to pair", async function () {
    expect(await Zap.from()).to.equal(ONE_ADDR);
    const expected = BigNumber.from("364666437843868998");
    const bal0Before = await Token1.balanceOf(owner.address);
    const bal1Before = await UniPair.balanceOf(owner.address);
    Token1.approve(Zap.address, ONE.mul(BigNumber.from(2)));
    await Zap.connect(owner).zapERC20(Token1.address, UniPair.address, ONE, 0);

    const bal0After = await Token1.balanceOf(owner.address);
    const bal1After = await UniPair.balanceOf(owner.address);
    
    expect(bal0Before.sub(bal0After)).to.be.equal(BigNumber.from("999807773387271607")); // small refund
    expect(bal1After.sub(bal1Before)).to.be.equal(expected);

    expect(await Zap.from()).to.equal(ONE_ADDR);
  });
  
  it("It should allow zapping from token1 to pair once more", async function () {
    expect(await Zap.from()).to.equal(ONE_ADDR);
    console.log(await UniPair.getReserves());
    console.log(await UniPair.totalSupply());
    const expected = BigNumber.from("363712505565613907");
    const bal0Before = await Token1.balanceOf(owner.address);
    const bal1Before = await UniPair.balanceOf(owner.address);
    Token1.approve(Zap.address, ONE.mul(BigNumber.from(2)));
    const tx = await Zap.connect(owner).zapERC20(Token1.address, UniPair.address, ONE, 0);
    const receipt = await tx.wait();

    const bal0After = await Token1.balanceOf(owner.address);
    const bal1After = await UniPair.balanceOf(owner.address);
    
    expect(bal0Before.sub(bal0After)).to.be.equal(BigNumber.from("999800948836728595")); // small refund
    expect(bal1After.sub(bal1Before)).to.be.equal(expected);

    expect(await Zap.from()).to.equal(ONE_ADDR);

    expect(receipt.gasUsed).to.eq(236024);
  });
});
