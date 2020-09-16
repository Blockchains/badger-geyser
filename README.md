# Badger Geyser
A smart-contract based mechanism to distribute tokens over time, inspired loosely by Compound and Uniswap. Based on the Ampleforth [Token Geyser](https://github.com/ampleforth/token-geyser/blob/master/contracts/BadgerGeyser.sol) implementation.

Within the Badger system, Geysers are used to mediate the initial distribution of BADGER and DIGG tokens.

Distribution tokens are added to a locked pool in the contract and become unlocked over time according to a once-configurable unlock schedule. Once unlocked, they are available to be claimed by users.

A user may deposit tokens to accrue ownership share over the unlocked pool. This owner share is a function of the number of tokens deposited as well as the length of time deposited.

Specifically, a user's share of the currently-unlocked pool equals their "deposit-seconds" divided by the global "deposit-seconds". 

Users are able to increase, decrease, or remove their staked tokens, and therefore their future share, at any time.

The audit for the original Ampleforth implementation audit can be found [here](https://github.com/ampleforth/ampleforth-audits/blob/master/token-geyser/v1.0.0/CertiK_Verification_Report.pdf)

# Contract Overview
The intent of the Geyser is to distribute the distributionToken over time according to the unlockSchedules. The unlockSchedules are set by the contract owner by locking the distributionToken via the lockTokens() method. Any user is able to gain a share of the distributionToken by staking the stakingToken within the Geyser. 

The Geyser is composed from several smart contract components:
- The Geyser contract itself
- Several TokenPool helper contracts to isolate balances for locked & unlocked distributionTokens, and staked stakingTokens.

## Modifications from Ampleforth
### Functionality
 - Each unlock schedule has a specified start time, allowing the Geyser to start distribution at a pre-configured time, rather than at the time the tokens are locked.

- There is a global start time, set on constructor. Before this time, no staking or unstaking can occur. Token locks cannot be scheduled before this time.

- There is an optional founder reward that distributes a fixed percentage of rewards to a fixed address. These are set on constructor and cannot be changed.

### Structure
The contract sturcture was modified slightly to allow for extensibility through inheritance, such as by the FutureGeyser, which is explained below.

- lockTokens() is split into an external and internal method (`_lockTokens()`)

- The bulk of functionality moved into the BaseGeyser contract, which is a parent of BadgerGeyser.

- All 'private' members and functions to were changed to 'internal' to allow visibility and modification by inheriting contracts.

## Future Geyser
A Geyser variant where the staking token must be set by the owner _after_ creation, rather than in the constructor. This allows for Geysers to be created which will be used with LP tokens that do not exist at creation. It's intended to be used with the StakingEscrow helper contract to pledge the tokens to the Geyser once the LP token is created. For safety, no token locking and subsequent staking & unstaking activities are possible before the token address is set.

#### Modifications
- Does not set stakingToken or create the _stakingPool TokenPool on constructor.
- The `setStakingToken()` method can be called by the owner to set the staking contract.
- After this point, it behaves identically to a standard BadgerGeyser.
- Public flag `isStakingTokenSet` can be read to see if the staking token is set.
- The `getStakingToken()` methods returns the 0 address before the staking token is set.

#### Intended Action Flow
1. The FutureGeyser & StakingEscrow are created, and the owner of the FutureGeyser is set to the StakingEscrow.
2. Funds intended to be distributed are deposited into the StakingEscrow.
3. The staking contract address is determined, and set on the Geyser by the StakingEscrow owner.
4. Tokens can now be locked from the StakingEscrow as the per standard variant, and staking can subsequently begin.

#### Founder Reward
When unstaking, a flat percentage of accured rewards can optionally be sent to a founder address, specified on contract creation.

## Configuration Notes
The configuration of the distribution pools used in the Badger system additionally 'removes' some functionality from the Ampleforth implementation.

### startBonus & bonusPeriodSec
- These parameters are used to reward users a higher proportion of shares for staking for longer periods of time
- This feature is not desired in Badger Geysers due to the short staking times, with a preference towards a simpler linear distribution.
- This feature is effectively disabled with the chosen values, as per the documentation
```
// If no period is desired, instead set startBonus = 100%
// and bonusPeriod to a small value like 1sec.
```
- In the Badger system, each staking pool has only one unlock schedule. The maxUnlockSchedules is set to 1 in the constructor to enforce this property.

#### founderRewardPercentage
10%

## Expected Behavior
The owner of the pool should be able to lock distribution tokens, to start unlocking at a specified time for a specified duration.
While the staking pool is active (after it's global start) users should be able to stake and unstake at-will. 

## Table of Contents

- [Install](#install)
- [Testing](#testing)
- [Contribute](#contribute)
- [License](#license)


## Install

```bash
# Install project dependencies
npm install

# Install ethereum local blockchain(s) and associated dependencies
npx setup-local-chains
```

## Testing

``` bash
# You can use the following command to start a local blockchain instance
npx start-chain [ganacheUnitTest|gethUnitTest]

# Run all unit tests
npm test

# Run unit tests in isolation
npx mocha test/staking.js --exit
```

## Contribute

To report bugs within this package, please create an issue in this repository.
When submitting code ensure that it is free of lint errors and has 100% test coverage.

``` bash
# Lint code
npm run lint

# View code coverage
npm run coverage
```

## License

[GNU General Public License v3.0 (c) 2020 Fragments, Inc.](./LICENSE)
