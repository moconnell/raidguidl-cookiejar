import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { Wallet } from "ethers";
import hre, { ethers, upgrades } from "hardhat";

import { ERC20 } from "./../../../app/types/typechain/@openzeppelin/contracts/token/ERC20/ERC20";
import { AvatarSetEvent, CookeJarV1 } from "./../../../app/types/typechain/contracts/CookieJarV1.sol/CookeJarV1";
import { CookieJarV1 } from "./../../../app/types/typechain/contracts/CookieJarV1.sol/CookieJarV1";
import { MockRaid } from "./../../../app/types/typechain/contracts/ERC20_Token.sol/MockRaid";
import { ERC20_Token } from "./../../../graph/generated/Token/ERC20_Token";

describe("Cookie jar unit tests", function () {
  const period = 1000;
  const cookieTokenValue = ethers.utils.parseEther("2");
  const maxCookiesPerPeriod = 1;

  let cookieJar: CookieJarV1;
  let erc20: MockRaid;
  let owner: SignerWithAddress;
  let user: SignerWithAddress;
  let moloch: Wallet;
  let avatar: Wallet;

  beforeEach("contract deployment", async function () {
    const signers = await ethers.getSigners();
    owner = signers[0];
    user = signers[1];

    moloch = ethers.Wallet.createRandom() as Wallet;
    avatar = ethers.Wallet.createRandom() as Wallet;

    const ERC20 = await ethers.getContractFactory("MockRaid");
    erc20 = (await ERC20.deploy(owner.address)) as unknown as MockRaid;

    erc20.connect(owner).mint(owner.address, ethers.utils.parseEther("1000"));

    // setup init params

    const _initializationParams = {
      _moloch: moloch.address,
      _token: erc20.address,
      _avatar: avatar.address,
      _cookieTokenValue: cookieTokenValue,
      _maxCookiesPerPeriod: maxCookiesPerPeriod,
      _period: period,
    };

    const cookieParams = ethers.utils.defaultAbiCoder.encode(
      [
        "tuple(address _moloch, address payable _token, address _avatar, uint256 _cookieTokenValue, uint256 _maxCookiesPerPeriod, uint256 _period) _initializationParams",
      ],
      [_initializationParams],
    );

    //deploy cookieJarv1

    const CookieJarV1 = await ethers.getContractFactory("CookieJarV1");
    cookieJar = (await upgrades.deployProxy(CookieJarV1, [cookieParams])) as CookieJarV1;
  });

  it("cookie jar should have correct parameters", async function () {
    expect(await cookieJar.period()).to.eq(period);
    expect(await cookieJar.cookieTokenValue()).to.eq(cookieTokenValue);
    expect(await cookieJar.maxCookiesPerPeriod()).to.eq(maxCookiesPerPeriod);
  });

  it("should grant user a membership", async function () {
    await expect(cookieJar.connect(owner).grantMembership(user.address)).to.not.be.reverted;
  });

  it("should add cookies to the cookie jar", async function () {
    const cookies = ethers.utils.parseEther("100");
    await erc20.connect(owner).approve(cookieJar.address, cookies);
    //deposit erc20
    await expect(cookieJar.connect(owner).deposit(cookies)).to.not.be.reverted;
    expect(await erc20.balanceOf(cookieJar.address)).to.equal(cookies);
  });

  it("should not be able to add non-cookie multiple amount to the cookie jar", async function () {
    const cookies = ethers.utils.parseEther("3");
    await erc20.connect(owner).approve(cookieJar.address, cookies);
    // try deposit erc20
    await expect(cookieJar.connect(owner).deposit(cookies)).to.be.reverted;
    expect(await erc20.balanceOf(cookieJar.address)).to.equal(0);
  });

  it("member should be able to withdraw cookies", async function () {
    const cookies = ethers.utils.parseEther("100");
    await erc20.connect(owner).approve(cookieJar.address, cookies);
    //deposit erc20
    await expect(cookieJar.connect(owner).deposit(cookies)).to.not.be.reverted;
    //add user as member
    await expect(cookieJar.connect(owner).grantMembership(user.address)).to.not.be.reverted;
    await expect(cookieJar.connect(user).claimCookies(1, "GIMMIE COOKIE!")).to.not.be.reverted;
    expect(await erc20.balanceOf(user.address)).to.equal(cookieTokenValue);
  });

  it("non-member should not be able to withdraw cookies", async function () {
    const cookies = ethers.utils.parseEther("100");
    await erc20.connect(owner).approve(cookieJar.address, cookies);
    //deposit erc20
    await expect(cookieJar.connect(owner).deposit(cookies)).to.not.be.reverted;
    await expect(cookieJar.connect(user).claimCookies(1, "GIMMIE COOKIE!")).to.be.reverted;
    expect(await erc20.balanceOf(user.address)).to.equal(0);
  });

  it("member should not be able to withdraw more than his allotted share of cookies", async function () {
    const cookies = ethers.utils.parseEther("100");
    await erc20.connect(owner).approve(cookieJar.address, cookies);
    //deposit erc20
    await expect(cookieJar.connect(owner).deposit(cookies)).to.not.be.reverted;
    //add user as member
    await expect(cookieJar.connect(owner).grantMembership(user.address)).to.not.be.reverted;
    await expect(cookieJar.connect(user).claimCookies(1, "GIMMIE COOKIE!")).to.not.be.reverted;
    await expect(cookieJar.connect(user).claimCookies(1, "GIMMIE COOKIE!")).to.be.reverted;
    expect(await erc20.balanceOf(user.address)).to.equal(cookieTokenValue);
  });
});
