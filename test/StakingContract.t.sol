// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {StakingContract} from "../src/StakingContract.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

contract StakingContractTest is Test {
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address owner = makeAddr("owner");
    StakingContract stakingContract;
    ERC20Mock token;

    function setUp() public {
        vm.startPrank(owner);
        token = new ERC20Mock();

        StakingContract stakingContractImplementation = new StakingContract();
        bytes memory initData = abi.encodeWithSignature("initialize(address,address)", address(token), owner);
        ERC1967Proxy proxy = new ERC1967Proxy(address(stakingContractImplementation), initData);
        stakingContract = StakingContract(address(proxy));

        token.mint(user1, 1000 ether);
        token.mint(user2, 1000 ether);
        vm.stopPrank();

        vm.prank(user1);
        token.approve(address(stakingContract), 1000 ether);

        vm.prank(user2);
        token.approve(address(stakingContract), 1000 ether);
    }

    function testStake() public {
        vm.prank(user1);
        stakingContract.stake(600 ether);

        assertEq(stakingContract.stakedBalance(user1), 600 ether);
    }

    function testStakewithoutBalance(address tempWallet) public {
        vm.assume(tempWallet != address(0));
        vm.assume(tempWallet != owner);
        vm.assume(tempWallet != user1);
        vm.assume(tempWallet != user2);

        vm.startPrank(tempWallet);
        token.approve(address(stakingContract), 500 ether);
        vm.expectRevert("Insufficient Balance");
        stakingContract.stake(500 ether);
        vm.stopPrank();
    }

    function testUnstake() public {
        vm.startPrank(user1);
        stakingContract.stake(500 ether);

        stakingContract.unstake(200 ether);
        vm.stopPrank();

        assertEq(stakingContract.stakedBalance(user1), 300 ether);

        (uint256 amount, uint256 unlockTime) = stakingContract.unstakingRequest(user1);
        assertEq(amount, 200 ether);
        assertEq(unlockTime, block.timestamp + 7 days);
    }

    function testUnstakeAndWithdraw() public {
        vm.startPrank(user1);
        stakingContract.stake(500 ether);

        stakingContract.unstake(300 ether);

        skip(7 days);
        stakingContract.withdraw();
        vm.stopPrank();
        (uint256 amount, uint256 unlockTime) = stakingContract.unstakingRequest(user1);
        assertEq(amount, 0);
        assertEq(unlockTime, 0);
        assertEq(token.balanceOf(user1), 800 ether);
    }

    function testCannotUnStakeZero() public {
        vm.prank(user1);
        vm.expectRevert("Cannot Unstake zero tokens");
        stakingContract.unstake(0);
    }

    function testCannotUnStakeMoreThanStaked() public {
        vm.startPrank(user1);
        stakingContract.stake(500 ether);

        vm.expectRevert("Insufficient staked balance");
        stakingContract.unstake(600 ether);
        vm.stopPrank();
    }

    function testCannotWithdrawEarly() public {
        vm.startPrank(user1);
        stakingContract.stake(500 ether);

        stakingContract.unstake(300 ether);

        vm.expectRevert("Unstake period not over");
        stakingContract.withdraw();
        vm.stopPrank();
    }
}
