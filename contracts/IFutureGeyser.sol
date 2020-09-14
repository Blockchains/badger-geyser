pragma solidity 0.5.0;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

contract IFutureGeyser {
    event StakingTokenSet(address stakingToken);

    function isStakingTokenSet() external view returns (bool);
    function getStakingToken() external view returns (IERC20);
    function setStakingToken(IERC20 stakingToken) external;

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
    ) external;
}
