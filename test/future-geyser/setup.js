const { contract, web3 } = require("@openzeppelin/test-environment");

const _require = require("app-root-path").require;
const BlockchainCaller = _require("/util/blockchain_caller");
const chain = new BlockchainCaller(web3);
const {
  $AMPL,
} = _require("/test/helper");

const AmpleforthErc20 = contract.fromArtifact("UFragments");
const FutureGeyser = contract.fromArtifact("FutureGeyser");
const StakingEscrow = contract.fromArtifact("StakingEscrow");

const InitialSharesPerToken = 10 ** 6;

let ampl, dist, stakingEscrow, owner, anotherAccount;

async function setupFutureGeyser(founderPercentage = 0) {
  const accounts = await chain.getUserAccounts();
  owner = web3.utils.toChecksumAddress(accounts[0]);
  anotherAccount = web3.utils.toChecksumAddress(accounts[8]);

  ampl = await AmpleforthErc20.new();
  await ampl.initialize(owner);
  await ampl.setMonetaryPolicy(owner);

  const userPercentage = 1 - founderPercentage;

  const startBonus = 100;
  const bonusPeriod = 1;

  dist = await FutureGeyser.new(
    ampl.address,
    1,
    startBonus,
    bonusPeriod,
    InitialSharesPerToken,
    0,
    owner,
    founderPercentage
  );

  stakingEscrow = await StakingEscrow.new(dist.address);
  await dist.transferOwnership(stakingEscrow.address);

  await ampl.transfer(anotherAccount, $AMPL(50000));
  await ampl.transfer(stakingEscrow.address, $AMPL(50000));
  await ampl.approve(dist.address, $AMPL(50000), { from: anotherAccount });
  await ampl.approve(dist.address, $AMPL(50000), { from: owner });

  return {
    ampl, dist, stakingEscrow, owner, anotherAccount, founderPercentage, userPercentage
  }
}

module.exports = {
  setupFutureGeyser
}