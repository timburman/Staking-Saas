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
        uint amount;
        uint startTime;
        uint lastClaimTime;
        uint totalRewardsCalimed;
        uint256 unlockTime;
        uint256 lastRewardCalculation;
        uint256 userRewardPerTokenPaid;
        uint256 pendingRewards;
    }


}