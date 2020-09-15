const { contract, web3 } = require("@openzeppelin/test-environment");
const {
  expectRevert,
  expectEvent,
  BN,
  constants,
} = require("@openzeppelin/test-helpers");
const { expect } = require("chai");


const _require = require("app-root-path").require;
const BlockchainCaller = _require("/util/blockchain_caller");
const chain = new BlockchainCaller(web3);
const { $AMPL, invokeRebase } = _require("/test/helper");

const AmpleforthErc20 = contract.fromArtifact("UFragments");
const BadgerGeyser = contract.fromArtifact("BadgerGeyser");

let owner, anotherAccount, ampl, dist, founderPercentage, userPercentage;

const defaultParams = {
  maxUnlockSchedules: 1,
  startBonus: 100,
  bonusPeriod: 1,
  initialSharesPerToken: 10 ** 6,
  globalStartTime: 0,
  founderPercentage: 0,
};

async function setupContracts(
  maxUnlockSchedules,
  startBonus,
  bonusPeriod,
  initialSharesPerToken,
  globalStartTime,
  founderPercentage
) {
  const accounts = await chain.getUserAccounts();
  owner = web3.utils.toChecksumAddress(accounts[0]);
  anotherAccount = web3.utils.toChecksumAddress(accounts[8]);

  userPercentage = 1 - founderPercentage;

  ampl = await AmpleforthErc20.new();
  await ampl.initialize(owner);
  await ampl.setMonetaryPolicy(owner);

  dist = await BadgerGeyser.new(
    ampl.address,
    ampl.address,
    maxUnlockSchedules,
    startBonus,
    bonusPeriod,
    initialSharesPerToken,
    globalStartTime,
    owner,
    founderPercentage
  );

  await ampl.transfer(anotherAccount, $AMPL(50000));

  return {
    owner,
    anotherAccount,
    ampl,
    dist,
    founderPercentage,
    userPercentage,
  };
}

module.exports = {
  setupContracts
}