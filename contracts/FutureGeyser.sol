pragma solidity 0.5.0;

import "./BadgerGeyser.sol";

/**
 * @title Badger Geyser (Initializable)
 * @dev A smart-contract based mechanism to distribute tokens over time, inspired loosely by
 *      Compound and Uniswap. Based on the Ampleforth implementation.
 *      (https://github.com/ampleforth/token-geyser/)
 *      
 *      Extends the BadgerGeyser logic to allow the staking address to be set after creation.
 *      This provides a non-custodial way to lock tokens for distribution, without knowing the staking asset at creation.
 *      It is intended to be used with a StakingEscrow to enforce this quality.
 */
contract FutureGeyser is BaseGeyser {
    using SafeMath for uint256;

    event StakingTokenSet(
        address stakingToken
    );

    // Initialization State
    bool public isStakingTokenSet = false;

    /**
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

    modifier onlyAfterStakingTokenSet() {
        require(isStakingTokenSet, "BadgerGeyser: Staking token not set");
        _;
    }

    /**
     * @return The token users deposit as stake. If not initialized, return 0 address
     */
    function getStakingToken() public view returns (IERC20) {
        if (isStakingTokenSet) {
            return _stakingPool.token();
        } else {
            return IERC20(address(0));
        }
    }

    /**
     * @notice Set staking token
     */
    function setStakingToken(IERC20 stakingToken) external onlyOwner {
        require(!isStakingTokenSet, "BadgerGeyser: Staking token already set");
        _stakingPool = new TokenPool(stakingToken);
        isStakingTokenSet = true;
        emit StakingTokenSet(address(stakingToken));
    }

    /**
     * @dev Transfers amount of deposit tokens from the user.
     * @param amount Number of deposit tokens to stake.
     * @param data Not used.
     */
    function stake(uint256 amount, bytes calldata data)
        external
        onlyAfterStart()
        onlyAfterStakingTokenSet()
    {
        _stakeFor(msg.sender, msg.sender, amount);
    }

    /**
     * @dev Transfers amount of deposit tokens from the caller on behalf of user.
     * @param user User address who gains credit for this stake operation.
     * @param amount Number of deposit tokens to stake.
     * @param data Not used.
     */
    function stakeFor(
        address user,
        uint256 amount,
        bytes calldata data
    ) external onlyAfterStart() onlyAfterStakingTokenSet() {
        _stakeFor(msg.sender, user, amount);
    }

    /**
     * @dev Unstakes a certain amount of previously deposited tokens. User also receives their
     * alotted number of distribution tokens.
     * @param amount Number of deposit tokens to unstake / withdraw.
     * @param data Not used.
     */
    function unstake(uint256 amount, bytes calldata data)
        external
        onlyAfterStart()
        onlyAfterStakingTokenSet()
    {
        _unstake(amount);
    }

    /**
     * @dev This funcion allows the contract owner to add more locked distribution tokens, along
     *      with the associated "unlock schedule". These locked tokens immediately begin unlocking
     *      linearly over the duraction of durationSec timeframe.
     * @param amount Number of distribution tokens to lock. These are transferred from the caller.
     * @param durationSec Length of time to linear unlock the tokens.
     * @param startTime Time to start distribution.
     */
    function lockTokens(
        uint256 amount,
        uint256 durationSec,
        uint256 startTime
    ) external onlyOwner onlyAfterStakingTokenSet() {
        _lockTokens(amount, durationSec, startTime);
    }
}
