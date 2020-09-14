pragma solidity 0.5.0;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./BaseGeyser.sol";

/**
 * @title Badger Geyser
 * @dev A smart-contract based mechanism to distribute tokens over time, inspired loosely by
 *      Compound and Uniswap. Based on the Ampleforth implementation.
 *      (https://github.com/ampleforth/token-geyser/)
 *
 *      Distribution tokens are added to a locked pool in the contract and become unlocked over time
 *      according to a once-configurable unlock schedule. Once unlocked, they are available to be
 *      claimed by users.
 *
 *      A user may deposit tokens to accrue ownership share over the unlocked pool. This owner share
 *      is a function of the number of tokens deposited as well as the length of time deposited.
 *      Specifically, a user's share of the currently-unlocked pool equals their "deposit-seconds"
 *      divided by the global "deposit-seconds".
 *
 *      More background and motivation available at:
 *      https://github.com/ampleforth/RFCs/blob/master/RFCs/rfc-1.md
 */
contract BadgerGeyser is BaseGeyser {
    using SafeMath for uint256;

    /**
     * @param stakingToken The token users deposit as stake.
     * @param distributionToken The token users receive as they unstake.
     * @param maxUnlockSchedules Max number of unlock stages, to guard against hitting gas limit.
     * @param startBonus_ Starting time bonus, BONUS_DECIMALS fixed point.
     *                    e.g. 25% means user gets 25% of max distribution tokens.
     * @param bonusPeriodSec_ Length of time for bonus to increase linearly to max.
     * @param initialSharesPerToken Number of shares to mint per staking token on first stake.
     * @param globalStartTime_ Timestamp after which unlock schedules and staking can begin.
     * @param founderRewardAddress_ Recipient address of founder rewards.
     * @param founderRewardPercentage_ Pecentage of rewards claimed to be distributed for founder address.
     */
    constructor(
        IERC20 stakingToken,
        IERC20 distributionToken,
        uint256 maxUnlockSchedules,
        uint256 startBonus_,
        uint256 bonusPeriodSec_,
        uint256 initialSharesPerToken,
        uint256 globalStartTime_,
        address founderRewardAddress_,
        uint256 founderRewardPercentage_
    ) public {
        // The start bonus must be some fraction of the max. (i.e. <= 100%)
        require(
            startBonus_ <= 10**BONUS_DECIMALS,
            "BadgerGeyser: start bonus too high"
        );

        // The founder reward must be some fraction of the max. (i.e. <= 100%)
        require(
            founderRewardPercentage_ <= 10**BONUS_DECIMALS,
            "BadgerGeyser: founder reward too high"
        );

        // If no period is desired, instead set startBonus = 100%
        // and bonusPeriod to a small value like 1sec.
        require(bonusPeriodSec_ != 0, "BadgerGeyser: bonus period is zero");
        require(
            initialSharesPerToken > 0,
            "BadgerGeyser: initialSharesPerToken is zero"
        );

        _stakingPool = new TokenPool(stakingToken);
        _unlockedPool = new TokenPool(distributionToken);
        _lockedPool = new TokenPool(distributionToken);
        startBonus = startBonus_;
        globalStartTime = globalStartTime_;
        bonusPeriodSec = bonusPeriodSec_;
        _maxUnlockSchedules = maxUnlockSchedules;
        _initialSharesPerToken = initialSharesPerToken;
        founderRewardPercentage = founderRewardPercentage_;
        founderRewardAddress = founderRewardAddress_;
    }
}
