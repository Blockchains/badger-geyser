pragma solidity 0.5.0;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "./IFutureGeyser.sol";

/**
 * @title A holder of tokens to be distributed via a Geyser.
 * Used in cases when a staking asset address is not known at the time of staking geyser creation.
 * Owner must be trusted to set the correct staking asset and distribute the tokens to the geyser.
 */
contract StakingEscrow is Ownable {
    IFutureGeyser public geyser;

    constructor(IFutureGeyser _geyser) public {
        geyser = _geyser;
    }

    function setStakingToken(IERC20 stakingToken) external onlyOwner {
        geyser.setStakingToken(stakingToken);
    }

    function approveStakingToken(uint256 amount) public onlyOwner {
        IERC20 stakingToken = geyser.getStakingToken();
        stakingToken.approve(address(geyser), amount);
    }

    function lockTokens(
        uint256 amount,
        uint256 durationSec,
        uint256 startTime
    ) external onlyOwner {
        approveStakingToken(amount);
        geyser.lockTokens(amount, durationSec, startTime);
    }
}
