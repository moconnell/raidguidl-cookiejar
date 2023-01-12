import { CookieJarV1 } from './../../../app/types/typechain/contracts/CookieJarV1.sol/CookieJarV1';
import { MockRaid } from './../../../app/types/typechain/contracts/ERC20_Token.sol/MockRaid';
import { ERC20 } from './../../../app/types/typechain/@openzeppelin/contracts/token/ERC20/ERC20';
import { ERC20_Token } from './../../../graph/generated/Token/ERC20_Token';
import { CookeJarV1, AvatarSetEvent } from './../../../app/types/typechain/contracts/CookieJarV1.sol/CookeJarV1';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import hre,{ ethers, upgrades } from "hardhat";
import { expect } from "chai";
import { Wallet } from 'ethers';

describe("Cookie jar unit tests", function () {
    let cookieJar: CookeJarV1;
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
        erc20 = await ERC20.deploy(owner.address) as unknown as MockRaid;

        erc20.connect(owner).mint(owner.address, ethers.utils.parseEther("1000"));

        // setup init params

        const _initializationParams = {
            _moloch: moloch.address,
            _token: erc20.address,
            _avatar: avatar.address,
            _cookieTokenValue: ethers.utils.parseEther("1"),
            _maxCookiesPerPeriod: 1,
            _period: 1000
        }

        const cookieParams = ethers.utils.defaultAbiCoder.encode(
            ["tuple(address _moloch, address payable _token, address _avatar, uint256 _cookieTokenValue, uint256 _maxCookiesPerPeriod, uint256 _period) _initializationParams"],
            [_initializationParams]);

            //deploy cookieJarv1

        const CookieJarV1 = await ethers.getContractFactory("CookieJarV1");
        cookieJar = await upgrades.deployProxy(CookieJarV1, [cookieParams]) as CookeJarV1;

    });

    it("cookie jar should have correct parameters", async function () {
        expect(await cookieJar.period()).to.eq(1000);
        expect(await cookieJar.cookieTokenValue()).to.eq(ethers.utils.parseEther("1"));
        expect(await cookieJar.maxCookiesPerPeriod()).to.eq(1);
    });

    it("should grant user a membership", async function() {
        await expect(cookieJar.connect(owner).grantMembership(user.address)).to.not.be.reverted;
    });

    it("Should add cookies to the cookie jar.", async function () {
        const cookies = ethers.utils.parseEther("100")
        await erc20.connect(owner).approve(cookieJar.address, cookies)
        //deposit erc20
        await expect(cookieJar.connect(owner).deposit(cookies)).to.not.be.reverted;
        //add user as member
        await expect(cookieJar.connect(owner).grantMembership(user.address)).to.not.be.reverted;
        expect(await erc20.balanceOf(cookieJar.address)).to.equal(cookies);
    });

    it("member should be able to withdraw cookies", async function() {
        const cookies = ethers.utils.parseEther("100")
        await erc20.connect(owner).approve(cookieJar.address, cookies)
        //deposit erc20
        await expect(cookieJar.connect(owner).deposit(cookies)).to.not.be.reverted;
        //add user as member
        await expect(cookieJar.connect(owner).grantMembership(user.address)).to.not.be.reverted;
        await expect(cookieJar.connect(user).claimCookies(1, "GIMMIE COOKIE!")).to.not.be.reverted;
        expect(await erc20.balanceOf(user.address)).to.equal(ethers.utils.parseEther("1"));
    });

    it("member should not be able to withdraw more than his allotted share of cookies", async function() {
        const cookies = ethers.utils.parseEther("100")
        await erc20.connect(owner).approve(cookieJar.address, cookies)
        //deposit erc20
        await expect(cookieJar.connect(owner).deposit(cookies)).to.not.be.reverted;
        //add user as member
        await expect(cookieJar.connect(owner).grantMembership(user.address)).to.not.be.reverted;
        await expect(cookieJar.connect(user).claimCookies(1, "GIMMIE COOKIE!")).to.not.be.reverted;
        await expect(cookieJar.connect(user).claimCookies(1, "GIMMIE COOKIE!")).to.be.reverted;
        expect(await erc20.balanceOf(user.address)).to.equal(ethers.utils.parseEther("1"));

    });

})