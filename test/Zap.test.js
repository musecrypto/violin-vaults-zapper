const { expect } = require("chai");
const { ethers } = require("hardhat");
const { BigNumber } = require("ethers");

const quickswap = "0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32";
const ZERO_ADDR = "0x0000000000000000000000000000000000000000";
const ONE_ADDR = "0x0000000000000000000000000000000000000001";

const ONE = ethers.utils.parseEther("1");

describe("Zap testing", function () {
  let Zap;
  let ZapHandlerV1;
  let UniFactory;
  let UniPair;
  let Main;
  let Main0Pair;
  let Main2Pair;
  let Token1Token2Pair;
  let Token0;
  let Token1;
  let Token2;
  

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
    const uniPairFactory = await ethers.getContractFactory("MockPair", owner);
    Zap = await ZapFactory.deploy();
    ZapHandlerV1 = await ZapHandlerV1Factory.deploy();

    Token0 = await TestTokenFactory.deploy("TestToken0", "TST");
    Token1 = await TestTokenFactory.deploy("TestToken1", "TST");
    Token2 = await TestTokenFactory.deploy("TestToken2", "TST");
    Main = await TestTokenFactory.deploy("Main", "MAIN");
    await Token0.connect(owner).mint(ethers.utils.parseEther("1000"));
    await Token1.connect(owner).mint(ethers.utils.parseEther("1000"));
    await Token2.connect(owner).mint(ethers.utils.parseEther("1000"));
    await Main.connect(owner).mint(ethers.utils.parseEther("1000"));
    
    await UniFactory.connect(owner).createPair(Token0.address, Token1.address);
    const pair = await UniFactory.getPair(Token0.address, Token1.address);
    UniPair = await uniPairFactory.attach(pair);
    await Token0.connect(owner).transfer(UniPair.address, ethers.utils.parseEther("100"));
    await Token1.connect(owner).transfer(UniPair.address, ethers.utils.parseEther("200"));
    await UniPair.connect(owner).mint(owner.address);
    
    await UniFactory.connect(owner).createPair(Main.address, Token0.address);
    const main0Pair = await UniFactory.getPair(Main.address, Token0.address);
    Main0Pair = await uniPairFactory.attach(main0Pair);
    await Token0.connect(owner).transfer(Main0Pair.address, ethers.utils.parseEther("100"));
    await Main.connect(owner).transfer(Main0Pair.address, ethers.utils.parseEther("200"));
    await Main0Pair.connect(owner).mint(owner.address);


    await UniFactory.connect(owner).createPair(Main.address, Token2.address);
    const main2Pair = await UniFactory.getPair(Main.address, Token2.address);
    Main2Pair = await uniPairFactory.attach(main2Pair);
    await Token2.connect(owner).transfer(Main2Pair.address, ethers.utils.parseEther("100"));
    await Main.connect(owner).transfer(Main2Pair.address, ethers.utils.parseEther("200"));
    await Main2Pair.connect(owner).mint(owner.address);

    await UniFactory.connect(owner).createPair(Token1.address, Token2.address);
    const token1Token2Pair = await UniFactory.getPair(Token1.address, Token2.address);
    Token1Token2Pair = await uniPairFactory.attach(token1Token2Pair);
    await Token2.connect(owner).transfer(Token1Token2Pair.address, ethers.utils.parseEther("100"));
    await Token1.connect(owner).transfer(Token1Token2Pair.address, ethers.utils.parseEther("200"));
    await Token1Token2Pair.connect(owner).mint(owner.address);
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
    await expect(Zap.connect(owner).swapERC20(Token0.address, Token1.address, owner.address, 100, 0))
      .to.be.revertedWith("!swap subroute not created yet");
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
    await expect(Zap.connect(owner).swapERC20(Token0.address, Token1.address, owner.address, 100, 0))
    .to.be.revertedWith("ERC20: transfer amount exceeds allowance");
  });

  it("It should allow zapping from token0 to token1 once approved", async function () {
    expect(await Zap.from()).to.equal(ONE_ADDR);
    const expected = BigNumber.from("1974316068794122597");
    await Token0.transfer(wallet1.address, ONE.mul(BigNumber.from(2)));
    await Token0.connect(wallet1).approve(Zap.address, ONE.mul(BigNumber.from(2)));
    const bal0Before = await Token0.balanceOf(wallet1.address);
    const bal1Before = await Token1.balanceOf(wallet1.address);

    await Zap.connect(wallet1).swapERC20(Token0.address, Token1.address, wallet1.address, ONE, 0);


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

    const tx = await Zap.connect(wallet1).swapERC20(Token0.address, Token1.address, wallet1.address, ONE, 0);
    const receipt = await tx.wait();

    const bal0After = await Token0.balanceOf(wallet1.address);
    const bal1After = await Token1.balanceOf(wallet1.address);
    
    expect(bal0Before.sub(bal0After)).to.be.equal(ONE);
    expect(bal1After.sub(bal1Before)).to.be.equal(expected);

    expect(await Zap.from()).to.equal(ONE_ADDR);
    
    expect(receipt.gasUsed).to.eq(118949);
  });

  it("It should allow zapping from token0 to token1 using cheaper method", async function () {
    expect(await Zap.from()).to.equal(ONE_ADDR);
    const expected = BigNumber.from("1898130556637140212");

    await Token0.transfer(wallet1.address, ONE);
    await Token0.connect(wallet1).approve(Zap.address, ONE);

    const bal0Before = await Token0.balanceOf(wallet1.address);
    const bal1Before = await Token1.balanceOf(wallet1.address);

    const tx = await Zap.connect(wallet1).swapERC20Fast(Token0.address, Token1.address, ONE);
    const receipt = await tx.wait();

    const bal0After = await Token0.balanceOf(wallet1.address);
    const bal1After = await Token1.balanceOf(wallet1.address);
    
    expect(bal0Before.sub(bal0After)).to.be.equal(ONE);
    expect(bal1After.sub(bal1Before)).to.be.equal(expected);

    expect(await Zap.from()).to.equal(ONE_ADDR);
    
    expect(receipt.gasUsed).to.eq(116072);
  });


  it("It should allow zapping from pair to token1", async function () {
    expect(await Zap.from()).to.equal(ONE_ADDR);
    const expected = BigNumber.from("2732496996611052997");
    const bal0Before = await UniPair.balanceOf(owner.address);
    const bal1Before = await Token1.balanceOf(owner.address);
    UniPair.approve(Zap.address, ONE.mul(BigNumber.from(2)));
    await Zap.connect(owner).swapERC20(UniPair.address, Token1.address, owner.address, ONE, 0);

    const bal0After = await UniPair.balanceOf(owner.address);
    const bal1After = await Token1.balanceOf(owner.address);
    
    expect(bal0Before.sub(bal0After)).to.be.equal(ONE);
    expect(bal1After.sub(bal1Before)).to.be.equal(expected);

    expect(await Zap.from()).to.equal(ONE_ADDR);
  });

  it("It should allow zapping from pair to token1 once more", async function () {
    expect(await Zap.from()).to.equal(ONE_ADDR);
    const expected = BigNumber.from("2713159995176661033");
    const bal0Before = await UniPair.balanceOf(owner.address);
    const bal1Before = await Token1.balanceOf(owner.address);
    const tx = await Zap.connect(owner).swapERC20(UniPair.address, Token1.address, owner.address, ONE, 0);
    const receipt = await tx.wait();

    const bal0After = await UniPair.balanceOf(owner.address);
    const bal1After = await Token1.balanceOf(owner.address);
    
    expect(bal0Before.sub(bal0After)).to.be.equal(ONE);
    expect(bal1After.sub(bal1Before)).to.be.equal(expected);

    expect(await Zap.from()).to.equal(ONE_ADDR);
    
    expect(receipt.gasUsed).to.eq(226744);
  });

  it("It should allow zapping from token1 to pair", async function () {
    expect(await Zap.from()).to.equal(ONE_ADDR);
    const expected = BigNumber.from("368231756829069951");
    const bal0Before = await Token1.balanceOf(owner.address);
    const bal1Before = await UniPair.balanceOf(owner.address);
    Token1.approve(Zap.address, ONE.mul(BigNumber.from(2)));
    await Zap.connect(owner).swapERC20(Token1.address, UniPair.address, owner.address, ONE, 0);

    const bal0After = await Token1.balanceOf(owner.address);
    const bal1After = await UniPair.balanceOf(owner.address);
    
    expect(bal0Before.sub(bal0After)).to.be.equal(BigNumber.from("999820556139247803")); // small refund
    expect(bal1After.sub(bal1Before)).to.be.equal(expected);

    expect(await Zap.from()).to.equal(ONE_ADDR);
  });
  
  it("It should allow zapping from token1 to pair once more", async function () {
    expect(await Zap.from()).to.equal(ONE_ADDR);
    const expected = BigNumber.from("367259107562107264");
    const bal0Before = await Token1.balanceOf(owner.address);
    const bal1Before = await UniPair.balanceOf(owner.address);
    Token1.approve(Zap.address, ONE.mul(BigNumber.from(2)));
    const tx = await Zap.connect(owner).swapERC20(Token1.address, UniPair.address, owner.address, ONE, 0);
    const receipt = await tx.wait();

    const bal0After = await Token1.balanceOf(owner.address);
    const bal1After = await UniPair.balanceOf(owner.address);
    
    expect(bal0Before.sub(bal0After)).to.be.equal(BigNumber.from("999813597790804314")); // small refund
    expect(bal1After.sub(bal1Before)).to.be.equal(expected);

    expect(await Zap.from()).to.equal(ONE_ADDR);

    expect(receipt.gasUsed).to.eq(236311);
  });

  it("It should allow setting a main token", async function () {
      await expect(ZapHandlerV1.setMainToken(Main.address))
        .to.emit(ZapHandlerV1, "MainTokenSet")
        .withArgs(Main.address);
      expect(await ZapHandlerV1.mainToken()).to.be.equal(Main.address);
  });

  it("It should allow adding token0<->main route", async function () {
    await expect(ZapHandlerV1.connect(owner).setRoute(Token0.address, Main.address, [Token0.address, quickswap, Main.address]))
      .to.emit(ZapHandlerV1, "RouteAdded")
    
    const routeStep= await (ZapHandlerV1.routes(Token0.address, Main.address, 0));
    expect(await ZapHandlerV1.routeLength(Token0.address, Main.address)).to.be.equal(1);
    expect(routeStep[0]).to.be.equal(Token0.address);
    expect(routeStep[1]).to.be.equal(Main.address);
    expect(routeStep[2]).to.be.equal(Main0Pair.address);
    expect(routeStep[3]).to.be.equal(997);
    expect(routeStep[4]).to.be.equal(1000);
    expect(await ZapHandlerV1.routeLength(Main.address, Token0.address)).to.be.equal(1);
  });
  it("It should allow adding token2<->main route", async function () {
    await expect(ZapHandlerV1.connect(owner).setRoute(Token2.address, Main.address, [Token2.address, quickswap, Main.address]))
      .to.emit(ZapHandlerV1, "RouteAdded")
    
    const routeStep= await (ZapHandlerV1.routes(Token2.address, Main.address, 0));
    expect(await ZapHandlerV1.routeLength(Token2.address, Main.address)).to.be.equal(1);
    expect(routeStep[0]).to.be.equal(Token2.address);
    expect(routeStep[1]).to.be.equal(Main.address);
    expect(routeStep[2]).to.be.equal(Main2Pair.address);
    expect(routeStep[3]).to.be.equal(997);
    expect(routeStep[4]).to.be.equal(1000);
    expect(await ZapHandlerV1.routeLength(Main.address, Token2.address)).to.be.equal(1);
  });


  it("It should allow zapping from token1 to token2 tunneling a route through main", async function () {
    expect(await Zap.from()).to.equal(ONE_ADDR);
    const expected = BigNumber.from("974604535974342600");
    const bal0Before = await Token0.balanceOf(owner.address);
    const bal1Before = await Token2.balanceOf(owner.address);
    Token0.approve(Zap.address, ONE.mul(BigNumber.from(2)));
    const tx = await Zap.connect(owner).swapERC20(Token0.address, Token2.address, owner.address, ONE, 0);
    const receipt = await tx.wait();

    const bal0After = await Token0.balanceOf(owner.address);
    const bal1After = await Token2.balanceOf(owner.address);
    
    expect(bal0Before.sub(bal0After)).to.be.equal(ONE);
    expect(bal1After.sub(bal1Before)).to.be.equal(expected);

    expect(await Zap.from()).to.equal(ONE_ADDR);

    expect(receipt.gasUsed).to.eq(537266);
  });


  it("It should allow zapping from token0 to token2 again ", async function () {
    expect(await Zap.from()).to.equal(ONE_ADDR);
    const expected = BigNumber.from("937227273667827351");
    const bal0Before = await Token0.balanceOf(owner.address);
    const bal1Before = await Token2.balanceOf(owner.address);
    Token0.approve(Zap.address, ONE.mul(BigNumber.from(2)));
    const tx = await Zap.connect(owner).swapERC20Fast(Token0.address, Token2.address, ONE);
    const receipt = await tx.wait();

    const bal0After = await Token0.balanceOf(owner.address);
    const bal1After = await Token2.balanceOf(owner.address);
    
    expect(bal0Before.sub(bal0After)).to.be.equal(ONE);
    expect(bal1After.sub(bal1Before)).to.be.equal(expected);

    expect(await Zap.from()).to.equal(ONE_ADDR);

    expect(receipt.gasUsed).to.eq(204431);
  });
  it("It should allow zapping from token0 to token1/token2 pair", async function () {
    expect(await Zap.from()).to.equal(ONE_ADDR);
    const expected = BigNumber.from("643829797386878814");
    const bal0Before = await Token0.balanceOf(owner.address);
    const bal1Before = await Token1Token2Pair.balanceOf(owner.address);
    Token0.approve(Zap.address, ONE.mul(BigNumber.from(2)));
    const tx = await Zap.connect(owner).swapERC20Fast(Token0.address, Token1Token2Pair.address, ONE);
    const receipt = await tx.wait();

    const bal0After = await Token0.balanceOf(owner.address);
    const bal1After = await Token1Token2Pair.balanceOf(owner.address);
    
    expect(bal0Before.sub(bal0After)).to.be.equal(ONE);
    expect(bal1After.sub(bal1Before)).to.be.equal(expected);

    expect(await Zap.from()).to.equal(ONE_ADDR);

    expect(receipt.gasUsed).to.eq(497756);
  });

  it("It should allow zapping from token0 to token1/token2 pair again", async function () {
    expect(await Zap.from()).to.equal(ONE_ADDR);
    const expected = BigNumber.from("631716686400380978");
    const bal0Before = await Token0.balanceOf(owner.address);
    const bal1Before = await Token1Token2Pair.balanceOf(owner.address);
    Token0.approve(Zap.address, ONE.mul(BigNumber.from(2)));
    const tx = await Zap.connect(owner).swapERC20Fast(Token0.address, Token1Token2Pair.address, ONE);
    const receipt = await tx.wait();

    const bal0After = await Token0.balanceOf(owner.address);
    const bal1After = await Token1Token2Pair.balanceOf(owner.address);
    
    expect(bal0Before.sub(bal0After)).to.be.equal(ONE);
    expect(bal1After.sub(bal1Before)).to.be.equal(expected);

    expect(await Zap.from()).to.equal(ONE_ADDR);

    expect(receipt.gasUsed).to.eq(399026);
  });
  it("It should allow zapping from token0 to token1/token2 pair with minimum", async function () {
    expect(await Zap.from()).to.equal(ONE_ADDR);
    const expected = BigNumber.from("619942319326980548");
    const bal0Before = await Token0.balanceOf(owner.address);
    const bal1Before = await Token1Token2Pair.balanceOf(owner.address);
    Token0.approve(Zap.address, ONE.mul(BigNumber.from(2)));
    const tx = await Zap.connect(owner).swapERC20(Token0.address, Token1Token2Pair.address, owner.address, ONE, expected);
    const receipt = await tx.wait();

    const bal0After = await Token0.balanceOf(owner.address);
    const bal1After = await Token1Token2Pair.balanceOf(owner.address);
    
    expect(bal0Before.sub(bal0After)).to.be.equal(ONE);
    expect(bal1After.sub(bal1Before)).to.be.equal(expected);

    expect(await Zap.from()).to.equal(ONE_ADDR);

    expect(receipt.gasUsed).to.eq(401881);
  });
  
  it("It should not allow zapping from token0 to token1/token2 pair with too high minimum", async function () {
    expect(await Zap.from()).to.equal(ONE_ADDR);
    const expected = BigNumber.from("619942319326980548");
    const bal0Before = await Token0.balanceOf(owner.address);
    const bal1Before = await Token1Token2Pair.balanceOf(owner.address);
    Token0.approve(Zap.address, ONE.mul(BigNumber.from(2)));
     await expect(Zap.connect(owner).swapERC20(Token0.address, Token1Token2Pair.address, owner.address, ONE, expected))
      .to.be.revertedWith("!minimum not received");
  });
});