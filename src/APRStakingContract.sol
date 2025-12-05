// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IStakingContract} from "./interfaces/IStakingContract.sol";

/**
 * @title APRStakingContract
 * @notice Staking contract with Annual Percentage Rate (APR) based rewards and time-locked unstaking
 * @dev Upgradeable implementation using UUPS pattern with APR cap mechanism
 */
contract APRStakingContract is Initializable, OwnableUpgradeable, ReentrancyGuard, UUPSUpgradeable, IStakingContract {
    // -- Constants --
    uint256 private constant SECONDS_IN_YEAR = 365 days;
    uint256 private constant BPS_DIVISOR = 10000;

    // State Variables
    IERC20 private _stakingToken;

    // -- Reward Variables --
    uint256 public rewardRate;
    uint256 public rewardDuration;
    uint256 public lastUpdateTime;
    uint256 public periodFinish;
    uint256 public maxAprInBps;

    // -- Reward Tracking --
    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    // -- Staking Balances --
    uint256 private _totalStaked;
    mapping(address => uint256) public stakedBalance;

    // -- Unstaking Time-lock Variables --
    struct UnstakeInfo {
        uint256 amount;
        uint256 unlockTime;
    }

    mapping(address => UnstakeInfo) public unstakingRequest;
    uint256 public unstakePeriod;

    struct AprStakeInfo {
        uint256 stakedAmount;
        uint256 earnedRewards;
        uint256 rewardPerTokenPaid;
        uint256 unstakeAmount;
        uint256 unlockTime;
    }

    // -- Events --
    event UnstakeInitiated(address indexed user, uint256 amount, uint256 unlockTime);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 newRewardRate);
    event RewardDurationUpdated(uint256 newDuration);
    event MaxAprUpdated(uint256 newMaxAprInBps);
    event UnstakePeriodUpdated(uint256 newPeriod);

    // -- Modifiers --
    modifier updateReward(address account) {
        _updateReward(account);
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param stakingToken_ Address of the token to be staked (also used for rewards)
     * @param initialMaxAprInBps_ Initial maximum APR in basis points
     * @param initialUnstakePeriod_ Initial unstaking lock period in seconds
     * @param initialRewardDuration_ Initial reward distribution duration
     * @param initialOwner Address of the contract owner
     */
    function initialize(
        address stakingToken_,
        uint256 initialMaxAprInBps_,
        uint256 initialUnstakePeriod_,
        uint256 initialRewardDuration_,
        address initialOwner
    ) public initializer {
        require(stakingToken_ != address(0), "Invalid staking token");
        require(initialOwner != address(0), "Invalid owner address");
        require(initialMaxAprInBps_ <= BPS_DIVISOR, "APR exceeds 100%");
        require(initialUnstakePeriod_ <= 30 days, "Unstake period too long");
        require(initialRewardDuration_ > 0, "Invalid reward duration");

        __Ownable_init(initialOwner);

        _stakingToken = IERC20(stakingToken_);
        maxAprInBps = initialMaxAprInBps_;
        unstakePeriod = initialUnstakePeriod_;
        rewardDuration = initialRewardDuration_;
    }

    // -- Views --

    /**
     * @notice Get total amount staked in the contract
     * @return Total staked amount
     */
    function totalStaked() external view returns (uint256) {
        return _totalStaked;
    }

    /**
     * @notice Get the staking token address
     * @return Address of the staking token
     */
    function stakingToken() external view override returns (address) {
        return address(_stakingToken);
    }

    function balanceOf(address account) external view returns (uint256) {
        return stakedBalance[account];
    }

    /**
     * @notice Get the last time rewards are applicable
     * @return Timestamp of last applicable reward time
     */
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /**
     * @notice Get available reward balance in contract
     * @return Available rewards (total balance minus staked amount)
     */
    function getAvailableRewardBalance() external view returns (uint256) {
        uint256 totalBalance = _stakingToken.balanceOf(address(this));
        return totalBalance > _totalStaked ? totalBalance - _totalStaked : 0;
    }

    /**
     * @notice Get comprehensive stake information for an account
     * @param account Address to query
     * @return APR-specific stake information
     */
    function getStakeInfo(address account) external view returns (AprStakeInfo memory) {
        UnstakeInfo memory request = unstakingRequest[account];
        return AprStakeInfo({
            stakedAmount: stakedBalance[account],
            earnedRewards: earned(account),
            rewardPerTokenPaid: userRewardPerTokenPaid[account],
            unstakeAmount: request.amount,
            unlockTime: request.unlockTime
        });
    }

    /**
     * @notice Calculates cumulative rewards per token. applying the APR cap.
     * @dev This is the core logic change. It determines the effective reward rate by comparing the owner-set rate with the rate required to meet the APR cap.
     * @return Reward per token stored value
     */
    function rewardPerToken() public view returns (uint256) {
        if (_totalStaked == 0) {
            return rewardPerTokenStored;
        }

        uint256 effectiveRewardRate = rewardRate;
        if (maxAprInBps > 0) {
            uint256 cappedRate = (_totalStaked * maxAprInBps) / SECONDS_IN_YEAR / BPS_DIVISOR;

            if (cappedRate < effectiveRewardRate) {
                effectiveRewardRate = cappedRate;
            }
        }

        return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * effectiveRewardRate * 1e18)
            / _totalStaked;
    }

    /**
     * @notice Calculate pending rewards for a staker
     * @param staker Address of the staker
     * @return Pending reward amount
     */
    function calculateReward(address staker) external view override returns (uint256) {
        return earned(staker);
    }

    /**
     * @notice Calculate earned rewards for an account
     * @param account Address to check
     * @return Earned rewards
     */
    function earned(address account) public view returns (uint256) {
        return (stakedBalance[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18 + rewards[account];
    }

    function getUnstakedRequest(address account) external view returns (uint256 amount, uint256 unlockTime) {
        UnstakeInfo storage request = unstakingRequest[account];
        return (request.amount, request.unlockTime);
    }

    // -- External Functions --

    /**
     * @notice Stake tokens
     * @param amount Amount of tokens to stake
     */
    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Staking: Cannot stake 0 tokens");
        unchecked {
            _totalStaked += amount;
            stakedBalance[msg.sender] += amount;
        }
        require(_stakingToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        emit Staked(msg.sender, amount);
    }

    /**
     * @notice Initiate unstaking process with time-lock
     * @param amount Amount of tokens to unstake
     */
    function unstake(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Staking: Cannot unstake 0 tokens");
        require(stakedBalance[msg.sender] >= amount, "Staking: Insufficient balance");
        require(unstakingRequest[msg.sender].amount == 0, "Staking: Unstake request already in progress");

        _totalStaked -= amount;
        stakedBalance[msg.sender] -= amount;

        uint256 unlockTime = block.timestamp + unstakePeriod;
        unstakingRequest[msg.sender] = UnstakeInfo({amount: amount, unlockTime: unlockTime});

        emit UnstakeInitiated(msg.sender, amount, unlockTime);
        emit Unstaked(msg.sender, amount);
    }

    function claimRewards() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            require(_stakingToken.transfer(msg.sender, reward), "Reward transfer failed");
            emit RewardClaimed(msg.sender, reward);
        }
    }

    function withdraw() external nonReentrant {
        UnstakeInfo storage request = unstakingRequest[msg.sender];
        require(request.amount > 0, "Withdraw: No unstake request found");
        require(block.timestamp >= request.unlockTime, "Withdraw: Unstake period not yet over");

        uint256 amountToWithdraw = request.amount;

        delete unstakingRequest[msg.sender];

        require(_stakingToken.transfer(msg.sender, amountToWithdraw), "Transfer failed");
        emit Withdrawn(msg.sender, amountToWithdraw);
    }

    function exit() external {
        claimRewards();

        uint256 balance = stakedBalance[msg.sender];
        if (balance > 0) {
            unstake(balance);
        }
    }

    // -- Owner-Only Functions --

    /**
     * @notice Called by the owner to start/top-up a rewards distribution period
     * @dev Owner must transfer the reward tokens to this contract before calling this function.
     */
    function notifyRewardAmount(uint256 reward) external onlyOwner updateReward(address(0)) {
        require(reward > 0, "Reward amount must be greater than 0");

        uint256 allowance = _stakingToken.allowance(msg.sender, address(this));
        require(allowance >= reward, "Insufficient token allowance");

        uint256 balanceBefore = _stakingToken.balanceOf(address(this));

        require(_stakingToken.transferFrom(msg.sender, address(this), reward), "Transfer Failed");

        uint256 balanceAfter = _stakingToken.balanceOf(address(this));
        require(balanceAfter >= balanceBefore + reward, "Token transfer failed or insufficient balance");

        if (block.timestamp >= periodFinish) {
            rewardRate = reward / rewardDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (reward + leftover) / rewardDuration;
        }

        require(rewardRate > 0, "Reward reate must be greater than 0");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardDuration;
        emit RewardRateUpdated(rewardRate);
    }

    function setRewardDuration(uint256 _rewardDuration) external onlyOwner {
        require(block.timestamp > periodFinish, "Cannot alter duration during an active reward period");
        rewardDuration = _rewardDuration;
        emit RewardDurationUpdated(_rewardDuration);
    }

    function setMaxApr(uint256 _newMaxAprInBps) external onlyOwner {
        require(_newMaxAprInBps <= BPS_DIVISOR, "APR exceeds 100%");
        maxAprInBps = _newMaxAprInBps;
        emit MaxAprUpdated(_newMaxAprInBps);
    }

    function setUnstakePeriod(uint256 _newPeriod) external onlyOwner {
        require(_newPeriod <= 30 days, "Unstake period cannot be more than 30 days");
        unstakePeriod = _newPeriod;
        emit UnstakePeriodUpdated(_newPeriod);
    }

    function _updateReward(address account) internal {
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        rewardPerTokenStored = rewardPerToken();
    }

    /**
     * @notice Authorize upgrade (only owner)
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    uint256[50] private _gap;
}
