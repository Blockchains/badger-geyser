pragma solidity 0.5.0;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./IStaking.sol";
import "./TokenPool.sol";

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
contract BaseGeyser is IStaking, Ownable {
    using SafeMath for uint256;

    event Staked(
        address indexed user,
        uint256 amount,
        uint256 total,
        bytes data
    );
    event Unstaked(
        address indexed user,
        uint256 amount,
        uint256 total,
        bytes data
    );
    event TokensClaimed(
        address indexed user,
        uint256 totalReward,
        uint256 userReward,
        uint256 founderReward
    );
    event TokensLocked(uint256 amount, uint256 durationSec, uint256 total);
    // amount: Unlocked tokens, total: Total locked tokens
    event TokensUnlocked(uint256 amount, uint256 total);

    TokenPool internal _stakingPool;
    TokenPool internal _unlockedPool;
    TokenPool internal _lockedPool;

    //
    // Time-bonus params
    //
    uint256 public constant BONUS_DECIMALS = 2;
    uint256 public startBonus = 0;
    uint256 public bonusPeriodSec = 0;
    uint256 public globalStartTime;

    //
    // Global accounting state
    //
    uint256 public totalLockedShares = 0;
    uint256 public totalStakingShares = 0;
    uint256 internal _totalStakingShareSeconds = 0;
    uint256 internal _lastAccountingTimestampSec = now;
    uint256 internal _maxUnlockSchedules = 0;
    uint256 internal _initialSharesPerToken = 0;

    //
    // User accounting state
    //
    // Represents a single stake for a user. A user may have multiple.
    struct Stake {
        uint256 stakingShares;
        uint256 timestampSec;
    }

    // Caches aggregated values from the User->Stake[] map to save computation.
    // If lastAccountingTimestampSec is 0, there's no entry for that user.
    struct UserTotals {
        uint256 stakingShares;
        uint256 stakingShareSeconds;
        uint256 lastAccountingTimestampSec;
    }

    // Aggregated staking values per user
    mapping(address => UserTotals) internal _userTotals;

    // The collection of stakes for each user. Ordered by timestamp, earliest to latest.
    mapping(address => Stake[]) internal _userStakes;

    //
    // Locked/Unlocked Accounting state
    //
    struct UnlockSchedule {
        uint256 initialLockedShares;
        uint256 unlockedShares;
        uint256 lastUnlockTimestampSec;
        uint256 endAtSec;
        uint256 durationSec;
        uint256 startTime;
    }

    UnlockSchedule[] public unlockSchedules;

    //
    // Founder Lock state
    //
    uint256 public constant MAX_PERCENTAGE = 100;
    uint256 public founderRewardPercentage = 0; //0% - 100%
    address public founderRewardAddress;


    modifier onlyAfterStart() {
        require(now >= globalStartTime, "BadgerGeyser: Distribution not started");
        _;
    }

    /**
     * @return The token users deposit as stake.
     */
    function getStakingToken() public view returns (IERC20) {
        return _stakingPool.token();
    }

    /**
     * @return The token users receive as they unstake.
     */
    function getDistributionToken() public view returns (IERC20) {
        assert(_unlockedPool.token() == _lockedPool.token());
        return _unlockedPool.token();
    }

    /**
     * @dev Transfers amount of deposit tokens from the user.
     * @param amount Number of deposit tokens to stake.
     * @param data Not used.
     */
    function stake(uint256 amount, bytes calldata data)
        external
        onlyAfterStart()
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
    ) external onlyAfterStart() {
        _stakeFor(msg.sender, user, amount);
    }

    /**
     * @dev Internal implementation of staking methods.
     * @param staker User address who deposits tokens to stake.
     * @param beneficiary User address who gains credit for this stake operation.
     * @param amount Number of deposit tokens to stake.
     */
    function _stakeFor(
        address staker,
        address beneficiary,
        uint256 amount
    ) internal {
        require(amount > 0, "BadgerGeyser: stake amount is zero");
        require(
            beneficiary != address(0),
            "BadgerGeyser: beneficiary is zero address"
        );
        require(
            totalStakingShares == 0 || totalStaked() > 0,
            "BadgerGeyser: Invalid state. Staking shares exist, but no staking tokens do"
        );

        uint256 mintedStakingShares = (totalStakingShares > 0)
            ? totalStakingShares.mul(amount).div(totalStaked())
            : amount.mul(_initialSharesPerToken);
        require(
            mintedStakingShares > 0,
            "BadgerGeyser: Stake amount is too small"
        );

        updateAccounting();

        // 1. User Accounting
        UserTotals storage totals = _userTotals[beneficiary];
        totals.stakingShares = totals.stakingShares.add(mintedStakingShares);
        totals.lastAccountingTimestampSec = now;

        Stake memory newStake = Stake(mintedStakingShares, now);
        _userStakes[beneficiary].push(newStake);

        // 2. Global Accounting
        totalStakingShares = totalStakingShares.add(mintedStakingShares);
        // Already set in updateAccounting()
        // _lastAccountingTimestampSec = now;

        // interactions
        require(
            _stakingPool.token().transferFrom(
                staker,
                address(_stakingPool),
                amount
            ),
            "BadgerGeyser: transfer into staking pool failed"
        );

        emit Staked(beneficiary, amount, totalStakedFor(beneficiary), "");
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
    {
        _unstake(amount);
    }

    /**
     * @param amount Number of deposit tokens to unstake / withdraw.
     * @return The total number of distribution tokens that would be rewarded.
     */
    function unstakeQuery(uint256 amount)
        public
        returns (
            uint256 totalReward,
            uint256 userReward,
            uint256 founderReward
        )
    {
        return _unstake(amount);
    }

    /**
     * @dev Unstakes a certain amount of previously deposited tokens. User also receives their
     * alotted number of distribution tokens.
     * @param amount Number of deposit tokens to unstake / withdraw.
     * @return The total number of distribution tokens rewarded.
     */
    function _unstake(uint256 amount)
        internal
        returns (
            uint256 totalReward,
            uint256 userReward,
            uint256 founderReward
        )
    {
        updateAccounting();

        // checks
        require(amount > 0, "BadgerGeyser: unstake amount is zero");
        require(
            totalStakedFor(msg.sender) >= amount,
            "BadgerGeyser: unstake amount is greater than total user stakes"
        );
        uint256 stakingSharesToBurn = totalStakingShares.mul(amount).div(
            totalStaked()
        );
        require(
            stakingSharesToBurn > 0,
            "BadgerGeyser: Unable to unstake amount this small"
        );

        // 1. User Accounting
        UserTotals storage totals = _userTotals[msg.sender];
        Stake[] storage accountStakes = _userStakes[msg.sender];

        // Redeem from most recent stake and go backwards in time.
        uint256 stakingShareSecondsToBurn = 0;
        uint256 sharesLeftToBurn = stakingSharesToBurn;
        uint256 rewardAmount = 0;
        while (sharesLeftToBurn > 0) {
            Stake storage lastStake = accountStakes[accountStakes.length - 1];
            uint256 stakeTimeSec = now.sub(lastStake.timestampSec);
            uint256 newStakingShareSecondsToBurn = 0;
            if (lastStake.stakingShares <= sharesLeftToBurn) {
                // fully redeem a past stake
                newStakingShareSecondsToBurn = lastStake.stakingShares.mul(
                    stakeTimeSec
                );
                rewardAmount = computeNewReward(
                    rewardAmount,
                    newStakingShareSecondsToBurn,
                    stakeTimeSec
                );
                stakingShareSecondsToBurn = stakingShareSecondsToBurn.add(
                    newStakingShareSecondsToBurn
                );
                sharesLeftToBurn = sharesLeftToBurn.sub(
                    lastStake.stakingShares
                );
                accountStakes.length--;
            } else {
                // partially redeem a past stake
                newStakingShareSecondsToBurn = sharesLeftToBurn.mul(
                    stakeTimeSec
                );
                rewardAmount = computeNewReward(
                    rewardAmount,
                    newStakingShareSecondsToBurn,
                    stakeTimeSec
                );
                stakingShareSecondsToBurn = stakingShareSecondsToBurn.add(
                    newStakingShareSecondsToBurn
                );
                lastStake.stakingShares = lastStake.stakingShares.sub(
                    sharesLeftToBurn
                );
                sharesLeftToBurn = 0;
            }
        }
        totals.stakingShareSeconds = totals.stakingShareSeconds.sub(
            stakingShareSecondsToBurn
        );
        totals.stakingShares = totals.stakingShares.sub(stakingSharesToBurn);
        // Already set in updateAccounting
        // totals.lastAccountingTimestampSec = now;

        // 2. Global Accounting
        _totalStakingShareSeconds = _totalStakingShareSeconds.sub(
            stakingShareSecondsToBurn
        );
        totalStakingShares = totalStakingShares.sub(stakingSharesToBurn);
        // Already set in updateAccounting
        // _lastAccountingTimestampSec = now;

        (userReward, founderReward) = computeFounderReward(rewardAmount);

        // interactions
        require(
            _stakingPool.transfer(msg.sender, amount),
            "BadgerGeyser: transfer out of staking pool failed"
        );

        if (userReward > 0) {
            require(
                _unlockedPool.transfer(msg.sender, userReward),
                "BadgerGeyser: transfer to user out of unlocked pool failed"
            );
        }

        if (founderReward > 0) {
            require(
                _unlockedPool.transfer(founderRewardAddress, founderReward),
                "BadgerGeyser: transfer to founder out of unlocked pool failed"
            );
        }

        emit Unstaked(msg.sender, amount, totalStakedFor(msg.sender), "");
        emit TokensClaimed(msg.sender, rewardAmount, userReward, founderReward);

        require(
            totalStakingShares == 0 || totalStaked() > 0,
            "BadgerGeyser: Error unstaking. Staking shares exist, but no staking tokens do"
        );
    }

    /**
     * @dev Determines split of specified reward amount between user and founder.
     * @param totalReward Amount of reward to split.
     * @return Reward amounts for user and founder.
     */
    function computeFounderReward(uint256 totalReward)
        public
        view
        returns (uint256 userReward, uint256 founderReward)
    {
        if (founderRewardPercentage == 0) {
            userReward = totalReward;
            founderReward = 0;
        } else if (founderRewardPercentage == 100) {
            userReward = 0;
            founderReward = totalReward;
        } else {
            founderReward = totalReward.mul(founderRewardPercentage).div(
                MAX_PERCENTAGE
            );
            userReward = totalReward.sub(founderReward); // Extra dust goes to use due to truncated rounding
        }
    }

    /**
     * @dev Applies an additional time-bonus to a distribution amount. This is necessary to
     *      encourage long-term deposits instead of constant unstake/restakes.
     *      The bonus-multiplier is the result of a linear function that starts at startBonus and
     *      ends at 100% over bonusPeriodSec, then stays at 100% thereafter.
     * @param currentRewardTokens The current number of distribution tokens already alotted for this
     *                            unstake op. Any bonuses are already applied.
     * @param stakingShareSeconds The stakingShare-seconds that are being burned for new
     *                            distribution tokens.
     * @param stakeTimeSec Length of time for which the tokens were staked. Needed to calculate
     *                     the time-bonus.
     * @return Updated amount of distribution tokens to award, with any bonus included on the
     *         newly added tokens.
     */
    function computeNewReward(
        uint256 currentRewardTokens,
        uint256 stakingShareSeconds,
        uint256 stakeTimeSec
    ) internal view returns (uint256) {
        uint256 newRewardTokens = totalUnlocked().mul(stakingShareSeconds).div(
            _totalStakingShareSeconds
        );

        if (stakeTimeSec >= bonusPeriodSec) {
            return currentRewardTokens.add(newRewardTokens);
        }

        uint256 oneHundredPct = 10**BONUS_DECIMALS;
        uint256 bonusedReward = startBonus
            .add(
            oneHundredPct.sub(startBonus).mul(stakeTimeSec).div(bonusPeriodSec)
        )
            .mul(newRewardTokens)
            .div(oneHundredPct);
        return currentRewardTokens.add(bonusedReward);
    }

    /**
     * @param addr The user to look up staking information for.
     * @return The number of staking tokens deposited for addr.
     */
    function totalStakedFor(address addr) public view returns (uint256) {
        return
            totalStakingShares > 0
                ? totalStaked().mul(_userTotals[addr].stakingShares).div(
                    totalStakingShares
                )
                : 0;
    }

    /**
     * @return The total number of deposit tokens staked globally, by all users.
     */
    function totalStaked() public view returns (uint256) {
        return _stakingPool.balance();
    }

    /**
     * @dev Note that this application has a staking token as well as a distribution token, which
     * may be different. This function is required by EIP-900.
     * @return The deposit token used for staking.
     */
    function token() external view returns (address) {
        return address(getStakingToken());
    }

    /**
     * @dev A globally callable function to update the accounting state of the system.
     *      Global state and state for the caller are updated.
     * @return [0] balance of the locked pool
     * @return [1] balance of the unlocked pool
     * @return [2] caller's staking share seconds
     * @return [3] global staking share seconds
     * @return [4] Total rewards caller has accumulated, including founder rewards, optimistically assumes max time-bonus.
     * @return [5] block timestamp
     * @return [6] Rewards caller has accumulated (minus founder rewards)
     * @return [7] Founder rewards portion of accumulation
     */
    function updateAccounting()
        public
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        unlockTokens();

        // Global accounting
        uint256 newStakingShareSeconds = now
            .sub(_lastAccountingTimestampSec)
            .mul(totalStakingShares);
        _totalStakingShareSeconds = _totalStakingShareSeconds.add(
            newStakingShareSeconds
        );
        _lastAccountingTimestampSec = now;

        // User Accounting
        UserTotals storage totals = _userTotals[msg.sender];
        uint256 newUserStakingShareSeconds = now
            .sub(totals.lastAccountingTimestampSec)
            .mul(totals.stakingShares);
        totals.stakingShareSeconds = totals.stakingShareSeconds.add(
            newUserStakingShareSeconds
        );
        totals.lastAccountingTimestampSec = now;

        uint256 totalUserRewards = (_totalStakingShareSeconds > 0)
            ? totalUnlocked().mul(totals.stakingShareSeconds).div(
                _totalStakingShareSeconds
            )
            : 0;

        (uint256 userRewards, uint256 founderRewards) = computeFounderReward(
            totalUserRewards
        );

        return (
            totalLocked(),
            totalUnlocked(),
            totals.stakingShareSeconds,
            _totalStakingShareSeconds,
            totalUserRewards,
            now,
            userRewards,
            founderRewards
        );
    }

    /**
     * @return Total number of locked distribution tokens.
     */
    function totalLocked() public view returns (uint256) {
        return _lockedPool.balance();
    }

    /**
     * @return Total number of unlocked distribution tokens.
     */
    function totalUnlocked() public view returns (uint256) {
        return _unlockedPool.balance();
    }

    /**
     * @return Number of unlock schedules.
     */
    function unlockScheduleCount() public view returns (uint256) {
        return unlockSchedules.length;
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
    ) external onlyOwner {
        _lockTokens(amount, durationSec, startTime);
    }

    function _lockTokens(
        uint256 amount,
        uint256 durationSec,
        uint256 startTime
    ) internal {
        require(
            unlockSchedules.length < _maxUnlockSchedules,
            "BadgerGeyser: reached maximum unlock schedules"
        );

        require(
            startTime >= globalStartTime,
            "BadgerGeyser: schedule cannot start before global start time"
        );

        // Update lockedTokens amount before using it in computations after.
        updateAccounting();

        uint256 lockedTokens = totalLocked();
        uint256 mintedLockedShares = (lockedTokens > 0)
            ? totalLockedShares.mul(amount).div(lockedTokens)
            : amount.mul(_initialSharesPerToken);

        UnlockSchedule memory schedule;
        schedule.initialLockedShares = mintedLockedShares;
        schedule.lastUnlockTimestampSec = startTime;
        schedule.endAtSec = startTime.add(durationSec);
        schedule.durationSec = durationSec;
        schedule.startTime = startTime;
        unlockSchedules.push(schedule);

        totalLockedShares = totalLockedShares.add(mintedLockedShares);

        require(
            _lockedPool.token().transferFrom(
                msg.sender,
                address(_lockedPool),
                amount
            ),
            "BadgerGeyser: transfer into locked pool failed"
        );
        emit TokensLocked(amount, durationSec, totalLocked());
    }

    /**
     * @dev Moves distribution tokens from the locked pool to the unlocked pool, according to the
     *      previously defined unlock schedules. Publicly callable.
     * @return Number of newly unlocked distribution tokens.
     */
    function unlockTokens() public returns (uint256) {
        uint256 unlockedTokens = 0;
        uint256 lockedTokens = totalLocked();

        if (totalLockedShares == 0) {
            unlockedTokens = lockedTokens;
        } else {
            uint256 unlockedShares = 0;
            for (uint256 s = 0; s < unlockSchedules.length; s++) {
                unlockedShares = unlockedShares.add(unlockScheduleShares(s));
            }
            unlockedTokens = unlockedShares.mul(lockedTokens).div(
                totalLockedShares
            );
            totalLockedShares = totalLockedShares.sub(unlockedShares);
        }

        if (unlockedTokens > 0) {
            require(
                _lockedPool.transfer(address(_unlockedPool), unlockedTokens),
                "BadgerGeyser: transfer out of locked pool failed"
            );
            emit TokensUnlocked(unlockedTokens, totalLocked());
        }

        return unlockedTokens;
    }

    /**
     * @dev Returns the number of unlockable shares from a given schedule. The returned value
     *      depends on the time since the last unlock. This function updates schedule accounting,
     *      but does not actually transfer any tokens.
     * @param s Index of the unlock schedule.
     * @return The number of unlocked shares.
     */
    function unlockScheduleShares(uint256 s) internal returns (uint256) {
        UnlockSchedule storage schedule = unlockSchedules[s];

        if (schedule.unlockedShares >= schedule.initialLockedShares) {
            return 0;
        }

        if (now < schedule.startTime) {
            return 0;
        }

        uint256 sharesToUnlock = 0;
        // Special case to handle any leftover dust from integer division
        if (now >= schedule.endAtSec) {
            sharesToUnlock = (
                schedule.initialLockedShares.sub(schedule.unlockedShares)
            );
            schedule.lastUnlockTimestampSec = schedule.endAtSec;
        } else {
            sharesToUnlock = now
                .sub(schedule.lastUnlockTimestampSec)
                .mul(schedule.initialLockedShares)
                .div(schedule.durationSec);
            schedule.lastUnlockTimestampSec = now;
        }

        schedule.unlockedShares = schedule.unlockedShares.add(sharesToUnlock);
        return sharesToUnlock;
    }
}