const { contract, web3 } = require("@openzeppelin/test-environment");
const {
  constants,
  expectRevert,
  expectEvent,
  BN,
  time,
} = require("@openzeppelin/test-helpers");
const { expect } = require("chai");
const { setupContractAndAccounts } = require("./setup");
const _require = require("app-root-path").require;
const BlockchainCaller = _require("/util/blockchain_caller");
const chain = new BlockchainCaller(web3);
const {
  $AMPL,
  invokeRebase,
  checkAmplAprox,
  TimeController,
  lockTokensAtLatestTime,
} = _require("/test/helper");

const AmpleforthErc20 = contract.fromArtifact("UFragments");
const FutureGeyser = contract.fromArtifact("FutureGeyser");
const StakingEscrow = contract.fromArtifact("StakingEscrow");
const TokenPool = contract.fromArtifact("TokenPool");

const InitialSharesPerToken = 10 ** 6;
const ONE_YEAR = 1 * 365 * 24 * 3600;
const ONE_DAY = 24 * 3600;

async function totalRewardsFor(account) {
  return (await dist.updateAccounting.call({ from: account }))[4];
}

let ampl, dist, stakingEscrow, owner, anotherAccount;
describe("General", function() {
  beforeEach("setup contracts", async function() {
    // const setup = await setupContractAndAccounts();
    // ampl = setup.ampl;
    // dist = setup.dist;
    // stakingEscrow = setup.stakingEscrow;
    // owner = setup.owner;
    // anotherAccount = setup.anotherAccount;
    ({
      ampl,
      dist,
      stakingEscrow,
      owner,
      anotherAccount,
    } = await setupContractAndAccounts());
  });

  it("non-owner should not be able to set staking token", async function() {
    await expectRevert(
      dist.setStakingToken(ampl.address, { from: anotherAccount }),
      "Ownable: caller is not the owner"
    );

    await expectRevert(
      dist.setStakingToken(ampl.address, { from: owner }),
      "Ownable: caller is not the owner"
    );
  });

  it("owner should be able to set staking token", async function() {
    await stakingEscrow.setStakingToken(ampl.address, {
      from: owner,
    });

    const events = await dist.getPastEvents("StakingTokenSet", {
      filter: { stakingToken: ampl.address },
      fromBlock: 0,
      toBlock: "latest",
    });
    expect(events[0].args.stakingToken).to.be.equal(ampl.address);
  });

  it("isStakingTokenSet should return false before set", async function() {
    const isSet = await dist.isStakingTokenSet();
    expect(isSet).to.be.equal(false);
  });

  it("getStakingToken should return 0 address before set", async function() {
    const stakingToken = await dist.getStakingToken();
    expect(stakingToken).to.be.equal(constants.ZERO_ADDRESS);
  });

  it("Non-owner should not be able to lock tokens before setting staking token", async function() {
    const now = await time.latest();

    let errorMessage;

    try {
      await dist.lockTokens($AMPL(100), ONE_DAY, now, { from: owner });
    } catch (error) {
      const actualError = error.message.replace(
        /Returned error: VM Exception while processing transaction: (revert )?/,
        ""
      );
      errorMessage = actualError;
    }
    expect(errorMessage, "Should revert").to.be.equal("Ownable: caller is not the owner -- Reason given: Ownable: caller is not the owner.");
  });

  it("Owner should not be able to lock tokens before setting staking token", async function() {
    const now = await time.latest();

    let errorMessage;

    try {
      await stakingEscrow.lockTokens($AMPL(100), ONE_DAY, now, { from: owner });
    } catch (error) {
      const actualError = error.message.replace(
        /Returned error: VM Exception while processing transaction: (revert )?/,
        ""
      );
      errorMessage = actualError;
    }
    expect(errorMessage, "Should revert").to.be.equal("revert");
  });

  it("Staking & unstaking should be impossible", async function() {
    await expectRevert(
      dist.stake($AMPL(50), [], { from: anotherAccount }),
      "BadgerGeyser: Staking token not set"
    );
    await expectRevert(
      dist.unstake($AMPL(50), [], { from: anotherAccount }),
      "BadgerGeyser: Staking token not set"
    );
  });

  describe("After staking token set", function() {
    beforeEach("set staking token", async function() {
      await stakingEscrow.setStakingToken(ampl.address);
    });

    it("owner should not be able to set staking token twice", async function() {
      await expectRevert(
        stakingEscrow.setStakingToken(ampl.address),
        "BadgerGeyser: Staking token already set"
      );
    });

    it("isStakingTokenSet should return true after set", async function() {
      const isSet = await dist.isStakingTokenSet();
      expect(isSet).to.be.equal(true);
    });

    it("getStakingToken should return proper address after set", async function() {
      const stakingToken = await dist.getStakingToken();
      expect(stakingToken).to.be.equal(ampl.address);
    });

    it("Owner should be able to lock tokens", async function() {
      const now = await time.latest();

      await stakingEscrow.lockTokens($AMPL(100), ONE_DAY, now, { from: owner });
    });

    describe("After tokens locked", function() {
      beforeEach("lock tokens", async function() {
        const now = await time.latest();

        await stakingEscrow.lockTokens($AMPL(1000), ONE_DAY, now, {
          from: owner,
        });
      });

      it("Users should be able to perform normal actions", async function() {
        await dist.stake($AMPL(50), [], { from: anotherAccount });
        await time.increase(30);
        await dist.unstake($AMPL(50), [], { from: anotherAccount });
      });
    });
  });
});
