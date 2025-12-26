// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IStakingContract} from "./interfaces/IStakingContract.sol";

contract StakingContract is Initializable, OwnableUpgradeable, ReentrancyGuard, UUPSUpgradeable, IStakingContract {
    IERC20 private _stakingToken;

    mapping(address => uint256) public stakedBalance;
    uint256 private _totalStaked;

    //Manage Unstaking Request
    struct UnstakeInfo {
        uint256 amount;
        uint256 unlockTime;
    }
    // Tracks Unstaking Requests

    mapping(address => UnstakeInfo) public unstakingRequest;

    uint256 public constant UNSTAKE_PERIOD = 7 days;

    // Events
    event UnstakeInitiated(address indexed user, uint256 amount, uint256 unlockTime);
    event Withdraw(address indexed user, uint256 amount);

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializer sets the address of the Governance Token
     * @param _tokenAddress The address to deploy _stakingToken contract
     * @param _initialOwner The address that will own the contract
     */
    function initialize(address _tokenAddress, address _initialOwner) public initializer {
        require(_tokenAddress != address(0), "The Token address cannot be zero");
        require(_initialOwner != address(0), "The Owner cannot be zero");
        __Ownable_init(_initialOwner);
        _stakingToken = IERC20(_tokenAddress);
    }

    // Staking

    /**
     * @notice Stakes a specified amount of _stakingToken.
     * @dev User must first approve this contract to spend their tokens.
     * @param amount The amount of tokens to stake.
     */
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot stake zero Tokens");
        require(_stakingToken.balanceOf(msg.sender) >= amount, "Insufficient Balance");
        require(_stakingToken.allowance(msg.sender, address(this)) >= amount, "Insufficient Allowance");

        // Transfer Tokens from user to the contract
        require(_stakingToken.transferFrom(msg.sender, address(this), amount), "Transfer Failed");

        // Updating Staking Records
        stakedBalance[msg.sender] = stakedBalance[msg.sender] + amount;
        _totalStaked = _totalStaked + amount;

        emit Staked(msg.sender, amount);
    }

    // UnStaking

    /**
     * @notice Initiates the unstaking process for a specified amount.
     * @dev Tokens remain locked for UNSTAKE_PERIOD. Only one unstake request active at a time per user.
     * @param amount The amount of tokens to start unstaking.
     */
    function unstake(uint256 amount) external nonReentrant {
        require(amount > 0, "Cannot Unstake zero tokens");
        require(stakedBalance[msg.sender] >= amount, "Insufficient staked balance");
        require(unstakingRequest[msg.sender].amount == 0, "Unstake Already in Process");

        // Updating Staking Records
        stakedBalance[msg.sender] -= amount;
        _totalStaked -= amount;

        // Recoring Unstaking
        uint256 unlockTime = block.timestamp + UNSTAKE_PERIOD;
        unstakingRequest[msg.sender] = UnstakeInfo({amount: amount, unlockTime: unlockTime});

        emit UnstakeInitiated(msg.sender, amount, unlockTime);
        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice Withdraws tokens after the unstaking period has passed.
     * @dev Can only be called after initiateUnstake and waiting UNSTAKE_PERIOD.
     */
    function withdraw() external nonReentrant {
        UnstakeInfo storage request = unstakingRequest[msg.sender];
        require(request.amount > 0, "No Unstake Request Found");
        require(block.timestamp >= request.unlockTime, "Unstake period not over");

        uint256 amountToWithdraw = request.amount;

        // Reset the unstake request before transfer
        request.amount = 0;
        request.unlockTime = 0;

        // Transfer
        require(_stakingToken.transfer(msg.sender, amountToWithdraw), "Token Transfer Failed during UnStaking Process");

        emit Withdraw(msg.sender, amountToWithdraw);
    }

    // View Functions

    /**
     * @notice Gets the staked balance of an account, which represents voting power.
     * @param _account The address to query.
     * @return The amount of tokens staked by the account.
     */
    function getVotingPower(address _account) external view returns (uint256) {
        return stakedBalance[_account];
    }

    /**
     * @notice Gets details of a pending unstake request for an account.
     * @param _account The address to query.
     * @return amount The amount pending withdrawal.
     * @return unlockTime The timestamp when withdrawal is possible.
     */
    function getUnstakedRequest(address _account) external view returns (uint256 amount, uint256 unlockTime) {
        UnstakeInfo storage request = unstakingRequest[_account];
        return (request.amount, request.unlockTime);
    }

    /**
     * @notice Calculate pending rewards (returns 0 for base staking)
     * @param staker Address of the staker
     * @return Pending reward amount (always 0)
     */
    function calculateReward(address staker) external pure override returns (uint256) {
        staker; // Silence unused parameter warning
        return 0;
    }

    /**
     * @notice Get total amount staked in the contract
     * @return Total staked amount
     */
    function totalStaked() external view override returns (uint256) {
        return _totalStaked;
    }

    /**
     * @notice Get the staking token address
     * @return Address of the staking token
     */
    function stakingToken() external view override returns (address) {
        return address(_stakingToken);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    uint256[50] private _gap;
}
