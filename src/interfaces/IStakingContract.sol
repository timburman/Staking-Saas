// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IStakingContract
 * @notice Standard interface for staking contracts.
 * @dev This interface defines the essential functions for staking operations.
 */
interface IStakingContract {
    /**
     * @notice Emitted when a user stakes tokens
     * @param user Address of the staker
     * @param amount Amount of tokens staked
     */
    event Staked(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user unstakes tokens
     * @param user Address of the staker
     * @param amount Amount of tokens unstaked
     */
    event Unstaked(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user claims rewards
     * @param user Address of the staker
     * @param reward Amount of rewards claimed
     */
    event RewardClaimed(address indexed user, uint256 reward);

    /**
     * @notice Stake tokens into the contract
     * @param amount Amount of tokens to stake
     */
    function stake(uint256 amount) external;

    /**
     * @notice Unstake staked tokens from the contract
     * @param amount Amount of tokens to unstake
     */
    function unstake(uint256 amount) external;

    /**
     * @notice Get stake information for a specific address
     * @param user Address of the user
     * @return Stake Information
     */
    function calculateReward(address staker) external view returns (uint256);

    /**
     * @notice Get total amount staked in the contract
     * @return Total staked amount
     */
    function totalStaked() external view returns (uint256);

    /**
     * @notice Get the staking token address
     * @return Address of the staking token
     */
    function stakingToken() external view returns (address);
}
