const { contract, web3 } = require('@openzeppelin/test-environment');
const {
  expectRevert,
  expectEvent,
  BN,
  constants,
  time
} = require('@openzeppelin/test-helpers');
const { expect } = require('chai');

const _require = require('app-root-path').require;
const BlockchainCaller = _require('/util/blockchain_caller');
const chain = new BlockchainCaller(web3);
const {
  $AMPL,
  invokeRebase,
  ONE_YEAR,
  setTimeForNextTransaction,
  increaseTimeForNextTransaction,
  setSnapshot,
  revertSnapshot
} = _require('/test/helper');

const { setupContracts } = require('./setup');

const AmpleforthErc20 = contract.fromArtifact('UFragments');
const BadgerGeyser = contract.fromArtifact('BadgerGeyser');
const InitialSharesPerToken = 10 ** 6;

const startBonus = 100;
const bonusPeriod = 1;

let ampl, dist, owner, anotherAccount;
let snapshotId;

let startTime, endStakeTime, stakeDuration;

describe('Time tests', function () {
  beforeEach('setup contracts', async function () {
    const now = await time.latest();
    startTime = now.add(new BN(1000));
    stakeDuration = new BN(1000);
    endStakeTime = startTime.add(stakeDuration);

    ({
      owner,
      anotherAccount,
      ampl,
      dist,
      founderPercentage,
      userPercentage
    } = await setupContracts(
      1,
      startBonus,
      bonusPeriod,
      InitialSharesPerToken,
      startTime.toNumber(),
      0,
      0
    ));

    await ampl.transfer(anotherAccount, $AMPL(50000));
    await ampl.approve(dist.address, $AMPL(50000), { from: anotherAccount });
    await ampl.approve(dist.address, $AMPL(50000), { from: owner });
  });

  describe('Staking before global time or tokens locked', function () {
    it('should fail', async function () {
      await expectRevert.unspecified(dist.stake($AMPL(0), []));
    });
  });

  it('Should not be possible to start unlockSchedule before global start time', async function () {
    await expectRevert(
      dist.lockTokens($AMPL(1000), ONE_YEAR, startTime.sub(new BN(1000))),
      'BadgerGeyser: schedule cannot start before global start time'
    );
  });

  it('Should not be possible to start unlockSchedule in the past', async function () {
    const now = await time.latest();
    await expectRevert(
      dist.lockTokens($AMPL(1000), ONE_YEAR, now - 1000),
      'BadgerGeyser: schedule cannot start before global start time'
    );
  });

  it('Should be possible to start unlockSchedule at global start time', async function () {
    await dist.lockTokens($AMPL(1000), ONE_YEAR, startTime);
  });

  it('Staking before global time', async function () {
    await dist.lockTokens($AMPL(1000), ONE_YEAR, startTime);
    await expectRevert(
      dist.stake($AMPL(500), [], { from: anotherAccount }),
      'BadgerGeyser: Distribution not started.'
    );
    await expectRevert(
      dist.stake($AMPL(500), [], { from: owner }),
      'BadgerGeyser: Distribution not started.'
    );
  });

  describe('Staking & Unstaking Timing - One User', function () {
    let preBalance;
    beforeEach(async function () {
      preBalance = await ampl.balanceOf(anotherAccount);
      await dist.lockTokens($AMPL(1000), ONE_YEAR, startTime);
    });

    it('Staking should fail before start time', async function () {
      await expectRevert(dist.stake($AMPL(500), [], { from: anotherAccount }), 'BadgerGeyser: Distribution not started');
    });

    it('Entire distribution to one staker, after unstaking complete', async function () {
      let now = await time.latest();
      await time.increase(startTime.sub(now).toNumber());

      await dist.stake($AMPL(500), [], { from: anotherAccount });

      now = await time.latest();
      await time.increase(endStakeTime.sub(now).toNumber());

      await dist.unstake($AMPL(500), [], { from: anotherAccount });

      const postBalance = await ampl.balanceOf(anotherAccount);
    });

    it('First stake exactly when last unlockSchedule is completed, first staker should be able to withdraw everything in next block', async function () {
      const preBalance = await ampl.balanceOf(anotherAccount);

      now = await time.latest();
      await time.increase((endStakeTime.sub(now)).toNumber());

      await dist.stake($AMPL(500), [], { from: anotherAccount });
      await time.increase(1);
      await time.advanceBlock();
      await dist.unstake($AMPL(500), [], { from: anotherAccount });

      const postBalance = await ampl.balanceOf(anotherAccount);
    });

    it('First stake well after last unlockSchedule is completed, first staker should be able to withdraw everything in next block', async function () {
      const preBalance = await ampl.balanceOf(anotherAccount);

      now = await time.latest();
      await time.increase((endStakeTime.sub(now).add(new BN(100000))).toNumber());

      await dist.stake($AMPL(500), [], { from: anotherAccount });
      await time.increase(1);
      await time.advanceBlock();
      await dist.unstake($AMPL(500), [], { from: anotherAccount });

      const postBalance = await ampl.balanceOf(anotherAccount);
    });
  });
});
