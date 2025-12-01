// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IStakingContract
 * @notice Standard interface for staking contracts.
 * @dev This interface defines the essential functions for staking operations.
 */
interface IStakingContract {
    /**
     * @notice Common base structure for stake information
     * @param amount Total amount staked by the user
     * @param startTime Timestamp when the stake was created
     * @param lastClaimTime Timestamp of the last reward claim
     * @param totalRewardsClaimed Cumulative rewards claimed by the user
     * @param unlockTime Timestamp when tokens can be unstaked (for lock-based)
     * @param lastRewardCalculation Timestamp of last reward calculation (for ASR)
     * @param userRewardPerTokenPaid Reward per token paid for user (for ASR)
     * @param pendingRewards Accumulated but unclaimed rewards (for ASR)
     */
    struct BaseStakeInfo {
        uint256 amount;
        uint256 startTime;
        uint256 lastClaimTime;
        uint256 totalRewardsCalimed;
        uint256 unlockTime;
        uint256 lastRewardCalculation;
        uint256 userRewardPerTokenPaid;
        uint256 pendingRewards;
    }

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
    function unstake(uint amount) external;

    /**
     * @notice Claim accumulated rewards
     */
    function claimReward() external;

    /**
     * @notice Get stake information for a specific address
     * @param user Address of the user
     * @return Stake Information
     */
    function getStakeInfo(address user) external view returns(BaseStakeInfo);

    /**
     * @notice Calculate pending rewards for a staker
     * @param staker Address of the staker
     * @return Pending reward amount
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
