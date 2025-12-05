// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {APRStakingContract} from "../src/APRStakingContract.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract APRStakingContractTest is Test {
    ERC20Mock public stakingToken;
    APRStakingContract public stakingContract;
    address public owner;
    address public user1;
    address public user2;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        stakingToken = new ERC20Mock();
        APRStakingContract stakingContractImpl = new APRStakingContract();
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,uint256,uint256,uint256,address)", address(stakingToken), 1000, 7 days, 30 days, owner
        );
        ERC1967Proxy proxyStakingContract = new ERC1967Proxy(address(stakingContractImpl), initData);
        stakingContract = APRStakingContract(address(proxyStakingContract));

        stakingToken.mint(user1, 1000 ether);
        stakingToken.mint(user2, 10000 ether);
        stakingToken.mint(owner, 1000000000 ether);
    }

    // -- Staking Tests --

    function testStakeIncreaseBalance() public {
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 500 ether);
        stakingContract.stake(500 ether);
        vm.stopPrank();

        assertEq(stakingContract.balanceOf(user1), 500 ether);
    }

    function testStakeEmitsEvent() public {
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 100 ether);
        vm.expectEmit(true, false, false, true);
        emit Staked(user1, 100 ether);
        stakingContract.stake(100 ether);
        vm.stopPrank();
    }

    function testStakeRevertsOnZero() public {
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 0);
        vm.expectRevert("Staking: Cannot stake 0 tokens");
        stakingContract.stake(0);
        vm.stopPrank();
    }

    // -- Rewards Logic --

    function testRewardActualWithCap() public {
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), 100 ether);
        stakingContract.stake(100 ether);
        vm.stopPrank();

        vm.startPrank(owner);
        stakingToken.approve(address(stakingContract), 10 ether);
        stakingContract.notifyRewardAmount(10 ether);

        vm.stopPrank();

        skip(1 days);

        uint256 beforeClaim = stakingToken.balanceOf(user1);
        vm.prank(user1);
        stakingContract.claimRewards();

        uint256 afterClaim = stakingToken.balanceOf(user1);
        uint256 actualReward = afterClaim - beforeClaim;

        uint256 maxApr = 1000;
        uint256 totalStaked = 100 ether;
        uint256 expectedCappedRate = (totalStaked * maxApr) / (365 days) / 10000;

        uint256 expectedReward = expectedCappedRate * 1 days;

        uint256 delta = 1e14;

        assertApproxEqAbs(actualReward, expectedReward, delta);
        emit log_named_uint("Claimed Reward", actualReward);
    }

    function testRewardRateUsedWhenBelowAPRCap() public {
        uint256 stakeAmount = 100 ether;
        uint256 rewardAmount = 0.05 ether; // small enough to be below the APR cap

        // user1 stakes
        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();

        // owner funds the rewards
        vm.startPrank(owner);
        stakingToken.approve(address(stakingContract), rewardAmount);
        stakingContract.notifyRewardAmount(rewardAmount);
        vm.stopPrank();

        // rewardRate = rewardAmount / rewardDuration = 0.05 ether / 30 days
        uint256 rewardRate = rewardAmount / 30 days;

        // APR cap rate = (stakeAmount * aprBps) / (365 days * BPS_DIVISOR)
        uint256 aprCapRate = (stakeAmount * 10000) / (365 days * 10000); // = stakeAmount / 365 days

        // Ensure rewardRate is below the APR cap (for test validity)
        assertLt(rewardRate, aprCapRate);

        // Advance 1 day
        skip(1 days);

        // Claim rewards
        uint256 beforeClaim = stakingToken.balanceOf(user1);
        vm.prank(user1);
        stakingContract.claimRewards();
        uint256 afterClaim = stakingToken.balanceOf(user1);
        uint256 actualReward = afterClaim - beforeClaim;

        // expectedReward = rewardRate * time
        uint256 expectedReward = rewardRate * 1 days;

        // Assert within tolerance
        assertApproxEqAbs(actualReward, expectedReward, 1e12); // ~0.000001 token margin
    }

    function testEarnedRewardIncreasesOverTime() public {
        uint256 stakeAmount = 100 ether;
        uint256 rewardAmount = 10 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();

        vm.startPrank(owner);
        stakingToken.approve(address(stakingContract), rewardAmount);
        stakingContract.notifyRewardAmount(rewardAmount);
        vm.stopPrank();

        skip(1 days);

        uint256 earned1 = stakingContract.earned(user1);

        skip(1 days);

        uint256 earned2 = stakingContract.earned(user1);

        assertGt(earned2, earned1, "Earned rewards should increase over time");
    }

    function testEarnedRewardWithZeroStaked() public view {
        uint256 earned = stakingContract.earned(user1);
        assertEq(earned, 0, "Earned rewards should be zero when no tokens are staked");
    }

    function testClaimRewardsTransferCorrectAmountandResetUserReward() public {
        uint256 stakeAmount = 100 ether;
        uint256 rewardAmount = 10 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();

        vm.startPrank(owner);
        stakingToken.approve(address(stakingContract), rewardAmount);
        stakingContract.notifyRewardAmount(rewardAmount);
        vm.stopPrank();

        skip(1 days);

        uint256 beforeClaim = stakingToken.balanceOf(user1);
        vm.prank(user1);
        stakingContract.claimRewards();

        uint256 afterClaim = stakingToken.balanceOf(user1);

        uint256 claimed = afterClaim - beforeClaim;
        assertGt(claimed, 0, "Claimed rewards should be greater than zero");

        uint256 postClaimedReward = stakingContract.earned(user1);
        assertEq(postClaimedReward, 0, "User's earned rewards should be reset after claiming");
    }

    function testClaimEmitsEvent() public {
        uint256 stakeAmount = 100 ether;
        uint256 rewardAmount = 10 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();

        vm.startPrank(owner);
        stakingToken.approve(address(stakingContract), rewardAmount);
        stakingContract.notifyRewardAmount(rewardAmount);
        vm.stopPrank();

        skip(1 days);

        vm.startPrank(user1);
        vm.expectEmit(true, false, false, true);
        emit RewardClaimed(user1, stakingContract.earned(user1));
        stakingContract.claimRewards();
        vm.stopPrank();
    }

    // -- Unstaking Tests --
    function testUnstakeLocksTokens() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        stakingContract.unstake(50 ether);
        vm.stopPrank();

        assertEq(
            stakingContract.balanceOf(user1), 50 ether, "User's balance should be reduced after initiating unstake"
        );
        (uint256 amount, uint256 unlockTime) = stakingContract.unstakingRequest(user1);
        assertEq(amount, 50 ether, "Unstake amount should match initiated amount");
        assertGt(unlockTime, block.timestamp, "Unlock time should be in the future");
    }

    function testunstakeRevertsOnZero() public {
        vm.startPrank(user1);
        vm.expectRevert("Staking: Cannot unstake 0 tokens");
        stakingContract.unstake(0);
        vm.stopPrank();
    }

    function testunstakeRevertsOnInsufficientBalance() public {
        vm.startPrank(user1);
        vm.expectRevert("Staking: Insufficient balance");
        stakingContract.unstake(100 ether);
        vm.stopPrank();
    }

    function testUnstakeDecreasesBalance() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        stakingContract.unstake(50 ether);
        vm.stopPrank();

        assertEq(stakingContract.balanceOf(user1), 50 ether, "User's balance should decrease after unstaking");
    }

    // -- Withdraw Tests --
    function testWithdrawAfterUnstakePeriod() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        stakingContract.unstake(50 ether);
        vm.stopPrank();

        skip(7 days); // Wait for the unstake period to end

        uint256 beforeWithdraw = stakingToken.balanceOf(user1);
        vm.startPrank(user1);
        stakingContract.withdraw();
        vm.stopPrank();

        uint256 afterWithdraw = stakingToken.balanceOf(user1);
        uint256 withdrawnAmount = afterWithdraw - beforeWithdraw;

        assertEq(withdrawnAmount, 50 ether, "Withdrawn amount should match unstaked amount");
    }

    function testWithdrawBeforeUnstakePeriodReverts() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        stakingContract.unstake(50 ether);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert("Withdraw: Unstake period not yet over");
        stakingContract.withdraw();
        vm.stopPrank();
    }

    function testCannotunstakeIfAlreadyInProgress() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        stakingContract.unstake(50 ether);
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert("Staking: Unstake request already in progress");
        stakingContract.unstake(20 ether);
        vm.stopPrank();
    }

    // -- Exit Tests --
    function testExitClaimsRewardsAndInitiatesUnstake() public {
        uint256 stakeAmount = 100 ether;
        uint256 rewardAmount = 10 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();

        vm.startPrank(owner);
        stakingToken.approve(address(stakingContract), rewardAmount);
        stakingContract.notifyRewardAmount(rewardAmount);
        vm.stopPrank();

        skip(1 days);

        uint256 beforeExit = stakingToken.balanceOf(user1);
        vm.startPrank(user1);
        stakingContract.exit();
        vm.stopPrank();
        uint256 afterExit = stakingToken.balanceOf(user1);
        uint256 claimedRewards = afterExit - beforeExit;

        assertGt(claimedRewards, 0, "User should claim rewards on exit");

        (uint256 unstakeAmount, uint256 unlockTime) = stakingContract.unstakingRequest(user1);
        assertGt(unstakeAmount, 0, "User should have unstaked tokens on exit");
        assertGt(unlockTime, block.timestamp, "Unstake unlock time should be in the future");
    }

    function testExitWithNoStakedTokens() public {
        uint256 balanceBeforeExit = stakingToken.balanceOf(user1);

        vm.prank(user1);
        stakingContract.exit();

        uint256 balanceAfterExit = stakingToken.balanceOf(user1);

        assertEq(balanceAfterExit, balanceBeforeExit, "Balance should remain unchanged when no tokens are staked");

        (uint256 unstakeAmount,) = stakingContract.unstakingRequest(user1);
        assertEq(unstakeAmount, 0, "Should have no unstake request when no tokens are staked");
    }

    // -- Owner-Only Functions Tests --

    function testNotifyRewardAmountSetsCorrectRewardRate() public {
        uint256 rewardAmount = 100 ether;

        vm.startPrank(owner);
        stakingToken.approve(address(stakingContract), rewardAmount);
        stakingContract.notifyRewardAmount(rewardAmount);
        vm.stopPrank();

        uint256 exprectedRewardRate = rewardAmount / 30 days;
        assertEq(stakingContract.rewardRate(), exprectedRewardRate, "Reward rate should be set correctly");
    }

    function testNotifyRewardAmountRevertsOnZero() public {
        vm.prank(owner);
        vm.expectRevert("Reward amount must be greater than 0");
        stakingContract.notifyRewardAmount(0);
    }

    function testNotifyRewardAmountRevertsOnInsufficientAllowance() public {
        uint256 rewardAmount = 100 ether;

        vm.startPrank(owner);
        stakingToken.approve(address(stakingContract), rewardAmount - 1);
        vm.expectRevert("Insufficient token allowance");
        stakingContract.notifyRewardAmount(rewardAmount);
        vm.stopPrank();
    }

    function testNotifyRewardAmountRevertsOnNonOwner() public {
        uint256 rewardAmount = 100 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), rewardAmount);
        vm.expectRevert();
        stakingContract.notifyRewardAmount(rewardAmount);
        vm.stopPrank();
    }

    function testNotifyRewardAmountExtendsPeriod() public {
        uint256 firstReward = 50 ether;
        uint256 secondReward = 30 ether;

        vm.startPrank(owner);
        stakingToken.approve(address(stakingContract), firstReward);
        stakingContract.notifyRewardAmount(firstReward);

        skip(15 days);

        stakingToken.approve(address(stakingContract), secondReward);
        stakingContract.notifyRewardAmount(secondReward);
        vm.stopPrank();

        assertGt(stakingContract.periodFinish(), block.timestamp + 29 days);
    }

    function testSetRewardDuration() public {
        uint256 newDuration = 60 days;

        vm.startPrank(owner);
        stakingContract.setRewardDuration(newDuration);
        vm.stopPrank();

        assertEq(stakingContract.rewardDuration(), newDuration, "Reward duration should be updated");
    }

    function testSetRewardDurationRevertsWhenActive() public {
        vm.startPrank(owner);
        stakingToken.approve(address(stakingContract), 100 ether);
        stakingContract.notifyRewardAmount(100 ether);

        vm.expectRevert("Cannot alter duration during an active reward period");
        stakingContract.setRewardDuration(60 days);
        vm.stopPrank();
    }

    function testSetRewardDurationRevertsOnNonOwner() public {
        vm.startPrank(user1);
        vm.expectRevert();
        stakingContract.setRewardDuration(60 days);
        vm.stopPrank();
    }

    function testSetMaxApr() public {
        uint256 newMaxApr = 2000;

        vm.startPrank(owner);
        stakingContract.setMaxApr(newMaxApr);
        vm.stopPrank();

        assertEq(stakingContract.maxAprInBps(), newMaxApr, "Max APR should be updated");
    }

    function testSetMaxAprRevertsOnInvalidValue() public {
        uint256 invalidApr = 10001;

        vm.startPrank(owner);
        vm.expectRevert("APR exceeds 100%");
        stakingContract.setMaxApr(invalidApr);
        vm.stopPrank();
    }

    function testSetMaxAprRevertsOnNonOwner() public {
        vm.startPrank(user1);
        vm.expectRevert();
        stakingContract.setMaxApr(2000);
        vm.stopPrank();
    }

    function testSetUnstakePeriod() public {
        uint256 newPeriod = 14 days;

        vm.startPrank(owner);
        stakingContract.setUnstakePeriod(newPeriod);
        vm.stopPrank();

        assertEq(stakingContract.unstakePeriod(), newPeriod, "Unstake period should be updated");
    }

    function testSetUnstakePeriodRevertsOnInvalidValue() public {
        uint256 invalidPeriod = 31 days;

        vm.startPrank(owner);
        vm.expectRevert("Unstake period cannot be more than 30 days");
        stakingContract.setUnstakePeriod(invalidPeriod);
        vm.stopPrank();
    }

    function testSetUnstakePeriodRevertsOnNonOwner() public {
        vm.startPrank(user1);
        vm.expectRevert();
        stakingContract.setUnstakePeriod(14 days);
        vm.stopPrank();
    }

    // -- Edge Cases and Integration Tests --

    function testMultipleUsersStakingAndClaiming() public {
        uint256 stakeAmount1 = 100 ether;
        uint256 stakeAmount2 = 200 ether;
        uint256 rewardAmount = 150 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), stakeAmount1);
        stakingContract.stake(stakeAmount1);
        vm.stopPrank();

        vm.startPrank(user2);
        stakingToken.approve(address(stakingContract), stakeAmount2);
        stakingContract.stake(stakeAmount2);
        vm.stopPrank();

        vm.startPrank(owner);
        stakingToken.approve(address(stakingContract), rewardAmount);
        stakingContract.notifyRewardAmount(rewardAmount);
        vm.stopPrank();

        skip(1 days);

        uint256 user1BalanceBefore = stakingToken.balanceOf(user1);
        vm.prank(user1);
        stakingContract.claimRewards();
        uint256 user1Reward = stakingToken.balanceOf(user1) - user1BalanceBefore;

        uint256 user2BalanceBefore = stakingToken.balanceOf(user2);
        vm.prank(user2);
        stakingContract.claimRewards();
        uint256 user2Reward = stakingToken.balanceOf(user2) - user2BalanceBefore;

        assertApproxEqRel(user2Reward, user1Reward * 2, 1e16); // 1% tolerance
    }

    function testStakeAfterUnstakeRequest() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);

        stakingContract.unstake(50 ether);

        stakingToken.approve(address(stakingContract), 25 ether);
        stakingContract.stake(25 ether);
        vm.stopPrank();

        assertEq(stakingContract.balanceOf(user1), 75 ether, "Should be able to stake after unstake request");
    }

    function testRewardCalculationWithZeroTotalSupply() public view {
        uint256 rewardPerToken = stakingContract.rewardPerToken();
        assertEq(rewardPerToken, 0, "Reward per token should be 0 when no tokens are staked");
    }

    function testGetAvailableRewardBalance() public {
        uint256 stakeAmount = 100 ether;
        uint256 rewardAmount = 50 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();

        vm.startPrank(owner);
        stakingToken.approve(address(stakingContract), rewardAmount);
        stakingContract.notifyRewardAmount(rewardAmount);
        vm.stopPrank();

        uint256 availableRewards = stakingContract.getAvailableRewardBalance();
        assertEq(availableRewards, rewardAmount, "Available reward balance should equal deposited rewards");
    }

    function testClaimRewardsWithZeroRewards() public {
        uint256 balanceBefore = stakingToken.balanceOf(user1);

        vm.prank(user1);
        stakingContract.claimRewards();

        uint256 balanceAfter = stakingToken.balanceOf(user1);
        assertEq(balanceAfter, balanceBefore, "Balance should not change when claiming zero rewards");
    }

    function testWithdrawWithoutUnstakeRequest() public {
        vm.startPrank(user1);
        vm.expectRevert("Withdraw: No unstake request found");
        stakingContract.withdraw();
        vm.stopPrank();
    }

    // -- Event Tests --

    function testNotifyRewardAmountEmitsEvent() public {
        uint256 rewardAmount = 100 ether;

        vm.startPrank(owner);
        stakingToken.approve(address(stakingContract), rewardAmount);

        vm.expectEmit(true, false, false, true);
        emit APRStakingContract.RewardRateUpdated(rewardAmount / 30 days);

        stakingContract.notifyRewardAmount(rewardAmount);
        vm.stopPrank();
    }

    function testSetMaxAprEmitsEvent() public {
        uint256 newMaxApr = 2000;

        vm.startPrank(owner);
        vm.expectEmit(true, false, false, true);
        emit APRStakingContract.MaxAprUpdated(newMaxApr);

        stakingContract.setMaxApr(newMaxApr);
        vm.stopPrank();
    }

    function testSetRewardDurationEmitsEvent() public {
        uint256 newDuration = 60 days;

        vm.startPrank(owner);
        vm.expectEmit(true, false, false, true);
        emit APRStakingContract.RewardDurationUpdated(newDuration);

        stakingContract.setRewardDuration(newDuration);
        vm.stopPrank();
    }

    function testunstakeEmitsEvent() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);

        vm.expectEmit(true, false, false, true);
        emit APRStakingContract.UnstakeInitiated(user1, 50 ether, block.timestamp + 7 days);

        stakingContract.unstake(50 ether);
        vm.stopPrank();
    }

    function testWithdrawEmitsEvent() public {
        uint256 stakeAmount = 100 ether;

        vm.startPrank(user1);
        stakingToken.approve(address(stakingContract), stakeAmount);
        stakingContract.stake(stakeAmount);
        stakingContract.unstake(50 ether);
        vm.stopPrank();

        skip(7 days);

        vm.startPrank(user1);
        vm.expectEmit(true, false, false, true);
        emit APRStakingContract.Withdrawn(user1, 50 ether);

        stakingContract.withdraw();
        vm.stopPrank();
    }
}
