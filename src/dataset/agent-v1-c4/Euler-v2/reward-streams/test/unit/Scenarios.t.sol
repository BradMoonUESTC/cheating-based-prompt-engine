// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "evc/EthereumVaultConnector.sol";
import "../harness/StakingRewardStreamsHarness.sol";
import "../harness/TrackingRewardStreamsHarness.sol";
import {MockERC20, MockERC20BalanceForwarder} from "../utils/MockERC20.sol";
import {MockController} from "../utils/MockController.sol";
import {boundAddr} from "../utils/TestUtils.sol";

contract ScenarioTest is Test {
    address internal PARTICIPANT_1;
    address internal PARTICIPANT_2;
    address internal PARTICIPANT_3;
    EthereumVaultConnector internal evc;
    StakingRewardStreamsHarness internal stakingDistributor;
    TrackingRewardStreamsHarness internal trackingDistributor;
    address internal stakingRewarded;
    address internal trackingRewarded;
    address internal reward;
    address internal seeder;

    function setUp() external {
        PARTICIPANT_1 = makeAddr("PARTICIPANT_1");
        PARTICIPANT_2 = makeAddr("PARTICIPANT_2");
        PARTICIPANT_3 = makeAddr("PARTICIPANT_3");

        evc = new EthereumVaultConnector();

        stakingDistributor = new StakingRewardStreamsHarness(address(evc), 10 days);
        trackingDistributor = new TrackingRewardStreamsHarness(address(evc), 10 days);

        stakingRewarded = address(new MockERC20("Staking Rewarded", "SRWDD"));
        vm.label(stakingRewarded, "STAKING REWARDED");

        trackingRewarded =
            address(new MockERC20BalanceForwarder(evc, trackingDistributor, "Tracking Rewarded", "SFRWDD"));
        vm.label(trackingRewarded, "TRACKING REWARDED");

        reward = address(new MockERC20("Reward", "RWD"));
        vm.label(reward, "REWARD");

        seeder = vm.addr(0xabcdef);
        vm.label(seeder, "SEEDER");

        MockERC20(reward).mint(seeder, 100e18);

        vm.prank(seeder);
        MockERC20(reward).approve(address(stakingDistributor), type(uint256).max);

        vm.prank(seeder);
        MockERC20(reward).approve(address(trackingDistributor), type(uint256).max);
    }

    // single rewarded and single reward; no participants so all the rewards should be earned by addresss(0)
    function test_Scenario_1(uint48 blockTimestamp, uint8 amountsLength, uint256 seed) external {
        blockTimestamp = uint48(bound(blockTimestamp, 1, type(uint48).max - 365 days));
        amountsLength = uint8(bound(amountsLength, 1, 25));

        vm.warp(blockTimestamp);

        // prepare the amounts
        uint128[] memory amounts = new uint128[](amountsLength);
        uint128 totalAmount = 0;
        for (uint256 i; i < amounts.length; ++i) {
            amounts[i] = uint128(uint256(keccak256(abi.encode(seed, i)))) % 2e18;
            totalAmount += amounts[i];
        }

        // register the distribution scheme in both distributors
        vm.startPrank(seeder);
        stakingDistributor.registerReward(stakingRewarded, reward, 0, amounts);
        trackingDistributor.registerReward(trackingRewarded, reward, 0, amounts);
        vm.stopPrank();

        // forward the time to the start of the distribution scheme
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1));

        // verify that address(0) hasn't earned anything yet
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0);

        // forward the time
        vm.warp(block.timestamp + (uint256(amountsLength) * 10 days) / 2);

        // verify that address(0) has earned rewards
        uint256 expectedAmount = 0;
        for (uint256 i; i <= amounts.length / 2; ++i) {
            if (i < amounts.length / 2) {
                expectedAmount += amounts[i];
            } else if (amounts.length % 2 == 1) {
                expectedAmount += amounts[i] / 2;
            }
        }
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), expectedAmount);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), expectedAmount);

        // claim the rewards earned by address(0)
        uint256 preClaimBalance = MockERC20(reward).balanceOf(address(this));
        stakingDistributor.updateReward(stakingRewarded, reward, address(this));
        assertEq(MockERC20(reward).balanceOf(address(this)), preClaimBalance + expectedAmount);

        preClaimBalance = MockERC20(reward).balanceOf(address(this));
        trackingDistributor.updateReward(trackingRewarded, reward, address(this));
        assertEq(MockERC20(reward).balanceOf(address(this)), preClaimBalance + expectedAmount);

        // verify total claimed
        assertEq(stakingDistributor.totalRewardClaimed(stakingRewarded, reward), expectedAmount);
        assertEq(trackingDistributor.totalRewardClaimed(trackingRewarded, reward), expectedAmount);

        // after claiming, rewards earned by address(0) should be zero
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0);

        // forward time to the end of the distribution scheme
        vm.warp(block.timestamp + (uint256(amountsLength) * 10 days) / 2);

        // verify that address(0) has earned all the rest of the rewards
        expectedAmount = totalAmount - expectedAmount;
        assertApproxEqAbs(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), expectedAmount, 1
        );
        assertApproxEqAbs(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), expectedAmount, 1
        );

        // only update the rewards
        stakingDistributor.updateReward(stakingRewarded, reward, address(0));
        preClaimBalance = MockERC20(reward).balanceOf(address(this));
        assertEq(MockERC20(reward).balanceOf(address(this)), preClaimBalance);

        trackingDistributor.updateReward(trackingRewarded, reward, address(0));
        preClaimBalance = MockERC20(reward).balanceOf(address(this));
        assertEq(MockERC20(reward).balanceOf(address(this)), preClaimBalance);

        // claim the rewards earned by address(0)
        preClaimBalance = MockERC20(reward).balanceOf(address(this));
        stakingDistributor.updateReward(stakingRewarded, reward, address(this));
        assertApproxEqAbs(MockERC20(reward).balanceOf(address(this)), preClaimBalance + expectedAmount, 1);

        preClaimBalance = MockERC20(reward).balanceOf(address(this));
        trackingDistributor.updateReward(trackingRewarded, reward, address(this));
        assertApproxEqAbs(MockERC20(reward).balanceOf(address(this)), preClaimBalance + expectedAmount, 1);

        // verify total claimed
        assertApproxEqAbs(stakingDistributor.totalRewardClaimed(stakingRewarded, reward), totalAmount, 1);
        assertApproxEqAbs(trackingDistributor.totalRewardClaimed(trackingRewarded, reward), totalAmount, 1);

        // after claiming, rewards earned by address(0) should be zero
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0);
    }

    // single rewarded and single reward; one participant who earns all the time
    function test_Scenario_2(uint48 blockTimestamp, uint8 amountsLength, uint256 seed, uint128 balance) external {
        blockTimestamp = uint48(bound(blockTimestamp, 1, type(uint48).max - 365 days));
        amountsLength = uint8(bound(amountsLength, 1, 25));
        balance = uint128(bound(balance, 1, 100e18));

        uint256 ALLOWED_DELTA = 1e12; // 0.0001%

        // mint the rewarded tokens to the participant
        vm.startPrank(PARTICIPANT_1);
        MockERC20(stakingRewarded).mint(PARTICIPANT_1, balance);
        MockERC20(trackingRewarded).mint(PARTICIPANT_1, balance);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);
        vm.stopPrank();

        vm.warp(blockTimestamp);

        // prepare the amounts
        uint128[] memory amounts = new uint128[](amountsLength);
        uint128 totalAmount = 0;
        for (uint256 i; i < amounts.length; ++i) {
            amounts[i] = uint128(uint256(keccak256(abi.encode(seed, i)))) % 2e18;
            totalAmount += amounts[i];
        }

        // register the distribution scheme in both distributors
        vm.startPrank(seeder);
        stakingDistributor.registerReward(stakingRewarded, reward, 0, amounts);
        trackingDistributor.registerReward(trackingRewarded, reward, 0, amounts);
        vm.stopPrank();

        // forward the time to the start of the distribution scheme
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1));

        // stake and enable rewards
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.stake(stakingRewarded, balance);
        stakingDistributor.enableReward(stakingRewarded, reward);

        MockERC20BalanceForwarder(trackingRewarded).enableBalanceForwarding();
        trackingDistributor.enableReward(trackingRewarded, reward);

        // verify that the participant hasn't earned anything yet
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 0);

        // verify balances and total eligible
        assertEq(stakingDistributor.balanceOf(PARTICIPANT_1, stakingRewarded), balance);
        assertEq(trackingDistributor.balanceOf(PARTICIPANT_1, trackingRewarded), balance);
        assertEq(stakingDistributor.totalRewardedEligible(stakingRewarded, reward), balance);
        assertEq(trackingDistributor.totalRewardedEligible(trackingRewarded, reward), balance);

        // forward the time
        vm.warp(block.timestamp + (uint256(amountsLength) * 10 days) / 2);

        // verify that the participant has earned rewards
        uint256 expectedAmount = 0;
        for (uint256 i; i <= amounts.length / 2; ++i) {
            if (i < amounts.length / 2) {
                expectedAmount += amounts[i];
            } else if (amounts.length % 2 == 1) {
                expectedAmount += amounts[i] / 2;
            }
        }
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false),
            expectedAmount,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false),
            expectedAmount,
            ALLOWED_DELTA
        );

        // update and claim the rewards earned by the participant (in two steps to check that both functions work)
        uint256 preClaimBalance = MockERC20(reward).balanceOf(PARTICIPANT_1);
        stakingDistributor.updateReward(stakingRewarded, reward, address(0));
        assertEq(MockERC20(reward).balanceOf(PARTICIPANT_1), preClaimBalance);

        stakingDistributor.claimReward(stakingRewarded, reward, PARTICIPANT_1, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_1), preClaimBalance + expectedAmount, ALLOWED_DELTA);

        preClaimBalance = MockERC20(reward).balanceOf(PARTICIPANT_1);
        trackingDistributor.updateReward(trackingRewarded, reward, address(0));
        assertEq(MockERC20(reward).balanceOf(PARTICIPANT_1), preClaimBalance);

        trackingDistributor.claimReward(trackingRewarded, reward, PARTICIPANT_1, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_1), preClaimBalance + expectedAmount, ALLOWED_DELTA);

        // verify total claimed
        assertApproxEqRel(stakingDistributor.totalRewardClaimed(stakingRewarded, reward), expectedAmount, ALLOWED_DELTA);
        assertApproxEqRel(
            trackingDistributor.totalRewardClaimed(trackingRewarded, reward), expectedAmount, ALLOWED_DELTA
        );

        // after claiming, rewards earned by the participant should be zero
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 0);

        // forward time to the end of the distribution scheme
        vm.warp(block.timestamp + (uint256(amountsLength) * 10 days) / 2);

        // verify that the participant has earned all the rest of the rewards
        expectedAmount = totalAmount - expectedAmount;
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false),
            expectedAmount,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false),
            expectedAmount,
            ALLOWED_DELTA
        );

        // claim the rewards earned by the participant (will be transferred to this contract)
        preClaimBalance = MockERC20(reward).balanceOf(address(this));
        stakingDistributor.claimReward(stakingRewarded, reward, address(this), false);
        assertApproxEqRel(MockERC20(reward).balanceOf(address(this)), preClaimBalance + expectedAmount, ALLOWED_DELTA);

        preClaimBalance = MockERC20(reward).balanceOf(address(this));
        trackingDistributor.claimReward(trackingRewarded, reward, address(this), false);
        assertApproxEqRel(MockERC20(reward).balanceOf(address(this)), preClaimBalance + expectedAmount, ALLOWED_DELTA);

        // verify total claimed
        assertApproxEqRel(stakingDistributor.totalRewardClaimed(stakingRewarded, reward), totalAmount, ALLOWED_DELTA);
        assertApproxEqRel(trackingDistributor.totalRewardClaimed(trackingRewarded, reward), totalAmount, ALLOWED_DELTA);

        // after claiming, rewards earned by the participant should be zero
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 0);

        // SANITY CHECKS

        // disable rewards
        stakingDistributor.disableReward(stakingRewarded, reward, false);
        trackingDistributor.disableReward(trackingRewarded, reward, false);

        // verify balances and total eligible
        assertEq(stakingDistributor.balanceOf(PARTICIPANT_1, stakingRewarded), balance);
        assertEq(trackingDistributor.balanceOf(PARTICIPANT_1, trackingRewarded), balance);
        assertEq(stakingDistributor.totalRewardedEligible(stakingRewarded, reward), 0);
        assertEq(trackingDistributor.totalRewardedEligible(trackingRewarded, reward), 0);

        // enable rewards
        stakingDistributor.enableReward(stakingRewarded, reward);
        trackingDistributor.enableReward(trackingRewarded, reward);

        // verify balances and total eligible
        assertEq(stakingDistributor.balanceOf(PARTICIPANT_1, stakingRewarded), balance);
        assertEq(trackingDistributor.balanceOf(PARTICIPANT_1, trackingRewarded), balance);
        assertEq(stakingDistributor.totalRewardedEligible(stakingRewarded, reward), balance);
        assertEq(trackingDistributor.totalRewardedEligible(trackingRewarded, reward), balance);

        // unstake and disable balance forwarding
        stakingDistributor.unstake(stakingRewarded, balance, PARTICIPANT_1, false);
        MockERC20BalanceForwarder(trackingRewarded).disableBalanceForwarding();

        // verify balances and total eligible
        assertEq(stakingDistributor.balanceOf(PARTICIPANT_1, stakingRewarded), 0);
        assertEq(trackingDistributor.balanceOf(PARTICIPANT_1, trackingRewarded), 0);
        assertEq(stakingDistributor.totalRewardedEligible(stakingRewarded, reward), 0);
        assertEq(trackingDistributor.totalRewardedEligible(trackingRewarded, reward), 0);

        // disable rewards
        stakingDistributor.disableReward(stakingRewarded, reward, false);
        trackingDistributor.disableReward(trackingRewarded, reward, false);

        // verify balances and total eligible
        assertEq(stakingDistributor.balanceOf(PARTICIPANT_1, stakingRewarded), 0);
        assertEq(trackingDistributor.balanceOf(PARTICIPANT_1, trackingRewarded), 0);
        assertEq(stakingDistributor.totalRewardedEligible(stakingRewarded, reward), 0);
        assertEq(trackingDistributor.totalRewardedEligible(trackingRewarded, reward), 0);
    }

    // single rewarded and single reward; one participant who doesn't earn all the time
    function test_Scenario_3(uint48 blockTimestamp, uint8 amountsLength, uint256 seed, uint128 balance) external {
        blockTimestamp = uint48(bound(blockTimestamp, 1, type(uint48).max - 365 days));
        amountsLength = uint8(bound(amountsLength, 1, 6)) * 4;
        balance = uint128(bound(balance, 2, 100e18));

        uint256 ALLOWED_DELTA = 1e12; // 0.0001%

        // mint the rewarded tokens to the participant
        vm.startPrank(PARTICIPANT_1);
        MockERC20(stakingRewarded).mint(PARTICIPANT_1, balance);
        MockERC20(trackingRewarded).mint(PARTICIPANT_1, balance);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);
        vm.stopPrank();

        vm.warp(blockTimestamp);

        // prepare the amounts
        uint128[] memory amounts = new uint128[](amountsLength);
        uint128 totalAmount = 0;
        for (uint256 i; i < amounts.length; ++i) {
            amounts[i] = uint128(uint256(keccak256(abi.encode(seed, i)))) % 2e18;
            totalAmount += amounts[i];
        }

        // register the distribution scheme in both distributors
        vm.startPrank(seeder);
        stakingDistributor.registerReward(stakingRewarded, reward, 0, amounts);
        trackingDistributor.registerReward(trackingRewarded, reward, 0, amounts);
        vm.stopPrank();

        // forward the time to the start of the distribution scheme
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1));

        // stake and enable rewards
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.stake(stakingRewarded, balance);
        stakingDistributor.enableReward(stakingRewarded, reward);

        MockERC20BalanceForwarder(trackingRewarded).enableBalanceForwarding();
        trackingDistributor.enableReward(trackingRewarded, reward);

        // forward the time
        vm.warp(block.timestamp + (uint256(amountsLength) * 10 days) / 4);

        // unstake/disable half of the balance
        stakingDistributor.unstake(stakingRewarded, balance / 2, PARTICIPANT_1, false);
        MockERC20(trackingRewarded).transfer(address(evc), balance / 2);

        // forward the time
        vm.warp(block.timestamp + (uint256(amountsLength) * 10 days) / 4);

        // disable the rewards for some time (now address(0) should be earning them)
        stakingDistributor.disableReward(stakingRewarded, reward, false);
        trackingDistributor.disableReward(trackingRewarded, reward, false);

        // forward the time
        vm.warp(block.timestamp + (uint256(amountsLength) * 10 days) / 4);

        // enable the rewards again
        stakingDistributor.enableReward(stakingRewarded, reward);
        trackingDistributor.enableReward(trackingRewarded, reward);

        // forward the time until the end of the distribution scheme
        vm.warp(block.timestamp + (uint256(amountsLength) * 10 days) / 4);

        // calculate how much address(0) should have earned (use the fact that amountsLength % 4 == 0)
        uint256 expectedAmount = 0;
        for (uint256 i = amounts.length / 2; i < 3 * amounts.length / 4; ++i) {
            expectedAmount += amounts[i];
        }

        // claim rewards for the participant and address(0)
        uint256 preClaimBalance = MockERC20(reward).balanceOf(PARTICIPANT_1);
        stakingDistributor.claimReward(stakingRewarded, reward, PARTICIPANT_1, false);
        assertApproxEqRel(
            MockERC20(reward).balanceOf(PARTICIPANT_1), preClaimBalance + totalAmount - expectedAmount, ALLOWED_DELTA
        );

        preClaimBalance = MockERC20(reward).balanceOf(PARTICIPANT_1);
        trackingDistributor.claimReward(trackingRewarded, reward, PARTICIPANT_1, false);
        assertApproxEqRel(
            MockERC20(reward).balanceOf(PARTICIPANT_1), preClaimBalance + totalAmount - expectedAmount, ALLOWED_DELTA
        );

        preClaimBalance = MockERC20(reward).balanceOf(PARTICIPANT_1);
        stakingDistributor.updateReward(stakingRewarded, reward, PARTICIPANT_1);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_1), preClaimBalance + expectedAmount, ALLOWED_DELTA);

        preClaimBalance = MockERC20(reward).balanceOf(PARTICIPANT_1);
        trackingDistributor.updateReward(trackingRewarded, reward, PARTICIPANT_1);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_1), preClaimBalance + expectedAmount, ALLOWED_DELTA);

        // verify total claimed
        assertApproxEqRel(stakingDistributor.totalRewardClaimed(stakingRewarded, reward), totalAmount, ALLOWED_DELTA);
        assertApproxEqRel(trackingDistributor.totalRewardClaimed(trackingRewarded, reward), totalAmount, ALLOWED_DELTA);

        // verify balances and total eligible
        assertApproxEqAbs(stakingDistributor.balanceOf(PARTICIPANT_1, stakingRewarded), balance / 2, 1);
        assertApproxEqAbs(trackingDistributor.balanceOf(PARTICIPANT_1, trackingRewarded), balance / 2, 1);
        assertApproxEqAbs(stakingDistributor.totalRewardedEligible(stakingRewarded, reward), balance / 2, 1);
        assertApproxEqAbs(trackingDistributor.totalRewardedEligible(trackingRewarded, reward), balance / 2, 1);
    }

    // single rewarded and single reward; multiple participants who don't earn all the time (hence address(0) earns some
    // rewards)
    function test_Scenario_4(uint48 blockTimestamp) external {
        blockTimestamp = uint48(bound(blockTimestamp, 1, type(uint48).max - 365 days));

        uint256 ALLOWED_DELTA = 1e12; // 0.0001%

        // mint the tracking rewarded token to address(1) as a placeholder address, allow participants to spend it
        vm.startPrank(address(1));
        MockERC20(trackingRewarded).mint(address(1), 10e18);
        MockERC20(trackingRewarded).approve(PARTICIPANT_1, type(uint256).max);
        MockERC20(trackingRewarded).approve(PARTICIPANT_2, type(uint256).max);
        vm.stopPrank();

        // mint the tokens to the participants
        vm.startPrank(PARTICIPANT_1);
        vm.label(PARTICIPANT_1, "PARTICIPANT_1");
        MockERC20(stakingRewarded).mint(PARTICIPANT_1, 10e18);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_2);
        vm.label(PARTICIPANT_2, "PARTICIPANT_2");
        MockERC20(stakingRewarded).mint(PARTICIPANT_2, 10e18);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);
        vm.stopPrank();

        vm.warp(blockTimestamp);

        // prepare the amounts; 5 epochs
        uint128[] memory amounts = new uint128[](5);
        amounts[0] = 5e18;
        amounts[1] = 10e18;
        amounts[2] = 15e18;
        amounts[3] = 5e18;
        amounts[4] = 10e18;

        // register the distribution scheme in both distributors
        vm.startPrank(seeder);
        stakingDistributor.registerReward(stakingRewarded, reward, 0, amounts);
        trackingDistributor.registerReward(trackingRewarded, reward, 0, amounts);
        vm.stopPrank();

        // forward the time to the start of the distribution scheme
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1));

        // participant 1 stakes and enables rewards, participant 2 doesn't do anything yet
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.stake(stakingRewarded, 1e18);
        stakingDistributor.enableReward(stakingRewarded, reward);

        MockERC20BalanceForwarder(trackingRewarded).enableBalanceForwarding();
        trackingDistributor.enableReward(trackingRewarded, reward);
        MockERC20(trackingRewarded).transferFrom(address(1), PARTICIPANT_1, 1e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 2.5 days);

        // PARTICIPANT_1 enables the same reward again (nothing should change; coverage)
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.enableReward(stakingRewarded, reward);
        trackingDistributor.enableReward(trackingRewarded, reward);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 2.5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 0);
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0);

        // participant 2 comes into play
        vm.startPrank(PARTICIPANT_2);
        stakingDistributor.stake(stakingRewarded, 1e18);
        stakingDistributor.enableReward(stakingRewarded, reward);

        MockERC20BalanceForwarder(trackingRewarded).enableBalanceForwarding();
        trackingDistributor.enableReward(trackingRewarded, reward);
        MockERC20(trackingRewarded).transferFrom(address(1), PARTICIPANT_2, 1e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 7.5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0);

        // participant 1 disables rewards
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.disableReward(stakingRewarded, reward, false);
        trackingDistributor.disableReward(trackingRewarded, reward, false);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 2.5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 5e18, ALLOWED_DELTA
        );
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0);

        // participant 1 enables rewards again and doubles down
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.stake(stakingRewarded, 1e18);
        stakingDistributor.enableReward(stakingRewarded, reward);

        MockERC20(trackingRewarded).transferFrom(address(1), PARTICIPANT_1, 1e18);
        trackingDistributor.enableReward(trackingRewarded, reward);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 8.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 8.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 6.666667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 6.666667e18, ALLOWED_DELTA
        );
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0);

        // both participants change their eligible balances
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.unstake(stakingRewarded, 1e18, PARTICIPANT_1, false);
        MockERC20(trackingRewarded).transfer(address(1), 1e18);
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_2);
        stakingDistributor.stake(stakingRewarded, 2e18);
        MockERC20(trackingRewarded).transferFrom(address(1), PARTICIPANT_2, 2e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 10.2083344e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false),
            10.2083344e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 12.291667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false),
            12.291667e18,
            ALLOWED_DELTA
        );
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0);

        // participant 1 adds more balance; both participants have equal eligible balances now
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.stake(stakingRewarded, 2e18);
        MockERC20(trackingRewarded).transferFrom(address(1), PARTICIPANT_1, 2e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 7.5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 14.583334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false),
            14.583334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 16.666667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false),
            16.666667e18,
            ALLOWED_DELTA
        );
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0);

        // both participants reduce their eligible balances to zero hence address(0) earns all the rewards in that
        // period
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.unstake(stakingRewarded, 3e18, PARTICIPANT_1, false);
        MockERC20(trackingRewarded).transfer(address(1), 3e18);
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_2);
        stakingDistributor.unstake(stakingRewarded, 3e18, PARTICIPANT_2, false);
        MockERC20(trackingRewarded).transfer(address(1), 3e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 2.5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 14.583334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false),
            14.583334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 16.666667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false),
            16.666667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1.25e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 1.25e18, ALLOWED_DELTA
        );

        // PARTICIPANT_2 adds eligible balance again, address(0) no longer earns rewards
        vm.startPrank(PARTICIPANT_2);
        stakingDistributor.stake(stakingRewarded, 5e18);
        MockERC20(trackingRewarded).transferFrom(address(1), PARTICIPANT_2, 5e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 2.5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 14.583334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false),
            14.583334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 17.916667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false),
            17.916667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1.25e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 1.25e18, ALLOWED_DELTA
        );

        // PARTICIPANT_1 joins PARTICIPANT_2 and adds the same eligible balance as PARTICIPANT_2
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.stake(stakingRewarded, 5e18);
        MockERC20(trackingRewarded).transferFrom(address(1), PARTICIPANT_1, 5e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 2.5 days);

        // PARTICIPANT_1 updates the reward data for himself, claiming the address(0) rewards
        vm.startPrank(PARTICIPANT_1);
        uint256 preBalance = MockERC20(reward).balanceOf(PARTICIPANT_1);
        stakingDistributor.updateReward(stakingRewarded, reward, PARTICIPANT_1);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_1), preBalance + 1.25e18, ALLOWED_DELTA);

        preBalance = MockERC20(reward).balanceOf(PARTICIPANT_1);
        trackingDistributor.updateReward(trackingRewarded, reward, PARTICIPANT_1);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_1), preBalance + 1.25e18, ALLOWED_DELTA);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 2.5 days);

        // PARTICIPANT_2 updates the reward data for himself too, but there's nothing to claim for address(0)
        vm.startPrank(PARTICIPANT_2);
        preBalance = MockERC20(reward).balanceOf(PARTICIPANT_2);
        stakingDistributor.updateReward(stakingRewarded, reward, PARTICIPANT_2);
        assertEq(MockERC20(reward).balanceOf(PARTICIPANT_2), preBalance);

        preBalance = MockERC20(reward).balanceOf(PARTICIPANT_2);
        trackingDistributor.updateReward(trackingRewarded, reward, PARTICIPANT_2);
        assertEq(MockERC20(reward).balanceOf(PARTICIPANT_2), preBalance);
        vm.stopPrank();

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 16.458334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false),
            16.458334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 19.791667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false),
            19.791667e18,
            ALLOWED_DELTA
        );
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0);

        // PARTICIPANT_2 reduces his eligible balance to zero
        vm.startPrank(PARTICIPANT_2);
        stakingDistributor.disableReward(stakingRewarded, reward, false);
        MockERC20BalanceForwarder(trackingRewarded).disableBalanceForwarding();
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 21.458334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false),
            21.458334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 19.791667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false),
            19.791667e18,
            ALLOWED_DELTA
        );
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0);

        // PARTICIPANT_1 opts out too; now address(0) earns all the rewards
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.unstake(stakingRewarded, 5e18, PARTICIPANT_1, false);
        trackingDistributor.disableReward(trackingRewarded, reward, false);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 2.5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 21.458334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false),
            21.458334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 19.791667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false),
            19.791667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );

        // PARTICIPANT_1 claims their rewards
        vm.startPrank(PARTICIPANT_1);
        preBalance = MockERC20(reward).balanceOf(PARTICIPANT_1);
        stakingDistributor.claimReward(stakingRewarded, reward, PARTICIPANT_1, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_1), preBalance + 21.458334e18, ALLOWED_DELTA);

        preBalance = MockERC20(reward).balanceOf(PARTICIPANT_1);
        trackingDistributor.claimReward(trackingRewarded, reward, PARTICIPANT_1, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_1), preBalance + 21.458334e18, ALLOWED_DELTA);
        vm.stopPrank();

        // PARTICIPANT_2 claims their rewards
        vm.startPrank(PARTICIPANT_2);
        preBalance = MockERC20(reward).balanceOf(PARTICIPANT_2);
        stakingDistributor.claimReward(stakingRewarded, reward, PARTICIPANT_2, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_2), preBalance + 19.791667e18, ALLOWED_DELTA);

        preBalance = MockERC20(reward).balanceOf(PARTICIPANT_2);
        trackingDistributor.claimReward(trackingRewarded, reward, PARTICIPANT_2, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_2), preBalance + 19.791667e18, ALLOWED_DELTA);
        vm.stopPrank();

        // PARTICIPANT_2 also claims the address(0) rewards
        preBalance = MockERC20(reward).balanceOf(PARTICIPANT_2);
        stakingDistributor.updateReward(stakingRewarded, reward, PARTICIPANT_2);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_2), preBalance + 2.5e18, ALLOWED_DELTA);

        preBalance = MockERC20(reward).balanceOf(PARTICIPANT_2);
        trackingDistributor.updateReward(trackingRewarded, reward, PARTICIPANT_2);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_2), preBalance + 2.5e18, ALLOWED_DELTA);

        // sanity checks
        vm.warp(block.timestamp + 50 days);
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 0);
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 0);
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0);
        assertEq(stakingDistributor.enabledRewards(PARTICIPANT_1, stakingRewarded)[0], reward);
        assertEq(stakingDistributor.enabledRewards(PARTICIPANT_2, stakingRewarded).length, 0);
        assertEq(trackingDistributor.enabledRewards(PARTICIPANT_1, trackingRewarded).length, 0);
        assertEq(trackingDistributor.enabledRewards(PARTICIPANT_2, trackingRewarded)[0], reward);
        assertEq(stakingDistributor.balanceOf(PARTICIPANT_1, stakingRewarded), 0);
        assertEq(stakingDistributor.balanceOf(PARTICIPANT_2, stakingRewarded), 5e18);
        assertEq(trackingDistributor.balanceOf(PARTICIPANT_1, trackingRewarded), 5e18);
        assertEq(trackingDistributor.balanceOf(PARTICIPANT_2, trackingRewarded), 0);
        assertEq(stakingDistributor.totalRewardedEligible(stakingRewarded, reward), 0);
        assertEq(trackingDistributor.totalRewardedEligible(trackingRewarded, reward), 0);
        assertEq(stakingDistributor.totalRewardRegistered(stakingRewarded, reward), 45e18);
        assertEq(trackingDistributor.totalRewardRegistered(trackingRewarded, reward), 45e18);
        assertApproxEqRel(stakingDistributor.totalRewardClaimed(stakingRewarded, reward), 45e18, ALLOWED_DELTA);
        assertApproxEqRel(trackingDistributor.totalRewardClaimed(trackingRewarded, reward), 45e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_1), 2 * 21.458334e18 + 2 * 1.25e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_2), 2 * 19.791667e18 + 2 * 2.5e18, ALLOWED_DELTA);
    }

    // single rewarded and multiple rewards; multiple participants who don't earn all the time (hence address(0) earns
    // some rewards)
    function test_Scenario_5(uint48 blockTimestamp) external {
        blockTimestamp = uint48(bound(blockTimestamp, 1, type(uint48).max - 365 days));

        uint256 ALLOWED_DELTA = 1e12; // 0.0001%

        // deploy another reward token, mint it to the seeder and approve both distributors
        vm.startPrank(seeder);
        address reward2 = address(new MockERC20("Reward2", "RWD2"));
        vm.label(reward2, "REWARD2");
        MockERC20(reward2).mint(seeder, 100e18);
        MockERC20(reward2).approve(address(stakingDistributor), type(uint256).max);
        MockERC20(reward2).approve(address(trackingDistributor), type(uint256).max);
        vm.stopPrank();

        // mint the tracking rewarded token to address(1) as a placeholder address, allow participants to spend it
        vm.startPrank(address(1));
        MockERC20(trackingRewarded).mint(address(1), 10e18);
        MockERC20(trackingRewarded).approve(PARTICIPANT_1, type(uint256).max);
        MockERC20(trackingRewarded).approve(PARTICIPANT_2, type(uint256).max);
        vm.stopPrank();

        // mint the tokens to the participants
        vm.startPrank(PARTICIPANT_1);
        vm.label(PARTICIPANT_1, "PARTICIPANT_1");
        MockERC20(stakingRewarded).mint(PARTICIPANT_1, 10e18);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_2);
        vm.label(PARTICIPANT_2, "PARTICIPANT_2");
        MockERC20(stakingRewarded).mint(PARTICIPANT_2, 10e18);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);
        vm.stopPrank();

        vm.warp(blockTimestamp);

        // prepare the amounts; 5 epochs
        uint128[] memory amounts1 = new uint128[](5);
        amounts1[0] = 2e18;
        amounts1[1] = 2e18;
        amounts1[2] = 0;
        amounts1[3] = 5e18;
        amounts1[4] = 10e18;

        uint128[] memory amounts2 = new uint128[](5);
        amounts2[0] = 0;
        amounts2[1] = 4e18;
        amounts2[2] = 1e18;
        amounts2[3] = 4e18;
        amounts2[4] = 10e18;

        // register the distribution schemes in both distributors
        vm.startPrank(seeder);
        stakingDistributor.registerReward(stakingRewarded, reward, 0, amounts1);
        stakingDistributor.registerReward(stakingRewarded, reward2, 0, amounts2);
        trackingDistributor.registerReward(trackingRewarded, reward, 0, amounts1);
        trackingDistributor.registerReward(trackingRewarded, reward2, 0, amounts2);
        vm.stopPrank();

        // forward the time to the start of the distribution scheme
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1));

        // participant 1: enables both rewards
        // participant 2: enables only reward2
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.enableReward(stakingRewarded, reward);
        stakingDistributor.enableReward(stakingRewarded, reward2);

        MockERC20BalanceForwarder(trackingRewarded).enableBalanceForwarding();
        trackingDistributor.enableReward(trackingRewarded, reward);
        trackingDistributor.enableReward(trackingRewarded, reward2);
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_2);
        stakingDistributor.enableReward(stakingRewarded, reward2);

        MockERC20BalanceForwarder(trackingRewarded).enableBalanceForwarding();
        trackingDistributor.enableReward(trackingRewarded, reward2);
        vm.stopPrank();

        // forward the time (address (0) earns rewards because none of the participants have eligible balances)
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 0);
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 0);
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward2, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward2, false), 0);
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward2, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward2, false), 0);
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward2, false), 0);

        // participant 1: has eligible balance for both rewards
        // participant 2: has eligible balance only for reward2
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.stake(stakingRewarded, 1e18);
        MockERC20(trackingRewarded).transferFrom(address(1), PARTICIPANT_1, 1e18);
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_2);
        stakingDistributor.stake(stakingRewarded, 2e18);
        MockERC20(trackingRewarded).transferFrom(address(1), PARTICIPANT_2, 2e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 0);
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward2, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward2, false), 0);
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward2, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward2, false), 0);
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward2, false), 0);

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 2e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 2e18, ALLOWED_DELTA
        );
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 0);
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward2, false), 0.666667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward2, false),
            0.666667e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward2, false), 1.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward2, false),
            1.333334e18,
            ALLOWED_DELTA
        );
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward2, false), 0);

        // participant 1: increases eligible balance for both rewards
        // participant 2: increases eligible balance for both rewards
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.stake(stakingRewarded, 1e18);
        MockERC20(trackingRewarded).transferFrom(address(1), PARTICIPANT_1, 1e18);
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_2);
        stakingDistributor.stake(stakingRewarded, 2e18);
        MockERC20(trackingRewarded).transferFrom(address(1), PARTICIPANT_2, 2e18);

        stakingDistributor.enableReward(stakingRewarded, reward);
        trackingDistributor.enableReward(trackingRewarded, reward);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 2.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 2.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 0.666667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 0.666667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward2, false), 1.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward2, false),
            1.333334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward2, false), 2.666667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward2, false),
            2.666667e18,
            ALLOWED_DELTA
        );
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward2, false), 0);

        // participant 1: disables reward2
        // participant 2: disables reward
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.disableReward(stakingRewarded, reward2, false);
        trackingDistributor.disableReward(trackingRewarded, reward2, false);
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_2);
        stakingDistributor.disableReward(stakingRewarded, reward, false);
        trackingDistributor.disableReward(trackingRewarded, reward, false);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 2.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 2.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 0.666667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 0.666667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward2, false), 1.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward2, false),
            1.333334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward2, false), 3.166667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward2, false),
            3.166667e18,
            ALLOWED_DELTA
        );
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward2, false), 0);

        // participant 1: enables reward2 again, but disables reward
        // participant 2: does nothing
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.enableReward(stakingRewarded, reward2);
        trackingDistributor.enableReward(trackingRewarded, reward2);
        stakingDistributor.disableReward(stakingRewarded, reward, false);
        trackingDistributor.disableReward(trackingRewarded, reward, false);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 2.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 2.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 0.666667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 0.666667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward2, false), 1.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward2, false), 1.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward2, false), 3.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward2, false), 3.5e18, ALLOWED_DELTA
        );
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward2, false), 0);

        // participant 1: gets rid of the eligible balance
        // participant 2: disables reward2, but enables reward
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.unstake(stakingRewarded, 2e18, PARTICIPANT_1, false);
        MockERC20(trackingRewarded).transfer(address(1), 2e18);
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_2);
        stakingDistributor.disableReward(stakingRewarded, reward2, false);
        trackingDistributor.disableReward(trackingRewarded, reward2, false);
        stakingDistributor.enableReward(stakingRewarded, reward);
        trackingDistributor.enableReward(trackingRewarded, reward);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 2.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 2.333334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 3.166667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 3.166667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward2, false), 1.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward2, false), 1.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward2, false), 3.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward2, false), 3.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 2e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward2, false), 2e18, ALLOWED_DELTA
        );

        // participant 1: increases eligible balance and enables both rewards
        // participant 2: does nothing
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.stake(stakingRewarded, 4e18);
        MockERC20(trackingRewarded).transferFrom(address(1), PARTICIPANT_1, 4e18);
        stakingDistributor.enableReward(stakingRewarded, reward);
        trackingDistributor.enableReward(trackingRewarded, reward);
        stakingDistributor.enableReward(stakingRewarded, reward2);
        trackingDistributor.enableReward(trackingRewarded, reward2);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 3.583334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 3.583334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 4.416667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 4.416667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward2, false), 3.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward2, false), 3.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward2, false), 3.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward2, false), 3.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 2e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward2, false), 2e18, ALLOWED_DELTA
        );

        // participant 1: disables reward2
        // participant 2: enables reward2
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.disableReward(stakingRewarded, reward2, false);
        trackingDistributor.disableReward(trackingRewarded, reward2, false);
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_2);
        stakingDistributor.enableReward(stakingRewarded, reward2);
        trackingDistributor.enableReward(trackingRewarded, reward2);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 6.083334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 6.083334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 6.916667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 6.916667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward2, false), 3.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward2, false), 3.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward2, false), 8.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward2, false), 8.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 2e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward2, false), 2e18, ALLOWED_DELTA
        );

        // participant 1: enables reward2 again, but reduces eligible balance
        // participant 2: disables reward and gets rid of the eligible balance
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.unstake(stakingRewarded, 2e18, PARTICIPANT_1, false);
        MockERC20(trackingRewarded).transfer(address(1), 2e18);
        stakingDistributor.enableReward(stakingRewarded, reward2);
        trackingDistributor.enableReward(trackingRewarded, reward2);
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_2);
        stakingDistributor.disableReward(stakingRewarded, reward, false);
        trackingDistributor.disableReward(trackingRewarded, reward, false);
        stakingDistributor.unstake(stakingRewarded, 4e18, PARTICIPANT_2, false);
        MockERC20(trackingRewarded).transfer(address(1), 4e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 11.083334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false),
            11.083334e18,
            ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 6.916667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 6.916667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 1e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward2, false), 8.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward2, false), 8.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward2, false), 8.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward2, false), 8.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 2e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward2, false), 2e18, ALLOWED_DELTA
        );

        // participant 1: disables both rewards and forfeits the most recent rewards (they should accrue to address(0)
        // because PARTICIPANT_2 has no eligible balance)
        // participant 2: increases eligible balance (it doesn't matter though because all the rewards are still earned
        // by address(0) - PARTICIPANT_2 has had no eligible balance)
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.disableReward(stakingRewarded, reward, true);
        trackingDistributor.disableReward(trackingRewarded, reward, true);
        stakingDistributor.disableReward(stakingRewarded, reward2, true);
        trackingDistributor.disableReward(trackingRewarded, reward2, true);
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_2);
        stakingDistributor.stake(stakingRewarded, 1e18);
        MockERC20(trackingRewarded).transferFrom(address(1), PARTICIPANT_2, 1e18);
        vm.stopPrank();

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 6.083334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 6.083334e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 6.916667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 6.916667e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 6e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 6e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward2, false), 3.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward2, false), 3.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward2, false), 8.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward2, false), 8.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 7e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward2, false), 7e18, ALLOWED_DELTA
        );

        // PARTICIPANT_1 claims rewards
        vm.startPrank(PARTICIPANT_1);
        uint256 preRewardBalance = MockERC20(reward).balanceOf(PARTICIPANT_1);
        stakingDistributor.claimReward(stakingRewarded, reward, PARTICIPANT_1, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_1), preRewardBalance + 6.083334e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward).balanceOf(PARTICIPANT_1);
        trackingDistributor.claimReward(trackingRewarded, reward, PARTICIPANT_1, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_1), preRewardBalance + 6.083334e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward2).balanceOf(PARTICIPANT_1);
        stakingDistributor.claimReward(stakingRewarded, reward2, PARTICIPANT_1, false);
        assertApproxEqRel(MockERC20(reward2).balanceOf(PARTICIPANT_1), preRewardBalance + 3.5e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward2).balanceOf(PARTICIPANT_1);
        trackingDistributor.claimReward(trackingRewarded, reward2, PARTICIPANT_1, false);
        assertApproxEqRel(MockERC20(reward2).balanceOf(PARTICIPANT_1), preRewardBalance + 3.5e18, ALLOWED_DELTA);
        vm.stopPrank();

        // PARTICIPANT_2 claims rewards
        vm.startPrank(PARTICIPANT_2);
        preRewardBalance = MockERC20(reward).balanceOf(PARTICIPANT_2);
        stakingDistributor.claimReward(stakingRewarded, reward, PARTICIPANT_2, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_2), preRewardBalance + 6.916667e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward).balanceOf(PARTICIPANT_2);
        trackingDistributor.claimReward(trackingRewarded, reward, PARTICIPANT_2, false);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_2), preRewardBalance + 6.916667e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward2).balanceOf(PARTICIPANT_2);
        stakingDistributor.claimReward(stakingRewarded, reward2, PARTICIPANT_2, false);
        assertApproxEqRel(MockERC20(reward2).balanceOf(PARTICIPANT_2), preRewardBalance + 8.5e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward2).balanceOf(PARTICIPANT_2);
        trackingDistributor.claimReward(trackingRewarded, reward2, PARTICIPANT_2, false);
        assertApproxEqRel(MockERC20(reward2).balanceOf(PARTICIPANT_2), preRewardBalance + 8.5e18, ALLOWED_DELTA);
        vm.stopPrank();

        // this contract claims whatever was earned by address(0)
        preRewardBalance = MockERC20(reward).balanceOf(address(this));
        stakingDistributor.updateReward(stakingRewarded, reward, address(this));
        assertApproxEqRel(MockERC20(reward).balanceOf(address(this)), preRewardBalance + 6e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward).balanceOf(address(this));
        trackingDistributor.updateReward(trackingRewarded, reward, address(this));
        assertApproxEqRel(MockERC20(reward).balanceOf(address(this)), preRewardBalance + 6e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward2).balanceOf(address(this));
        stakingDistributor.updateReward(stakingRewarded, reward2, address(this));
        assertApproxEqRel(MockERC20(reward2).balanceOf(address(this)), preRewardBalance + 7e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward2).balanceOf(address(this));
        trackingDistributor.updateReward(trackingRewarded, reward2, address(this));
        assertApproxEqRel(MockERC20(reward2).balanceOf(address(this)), preRewardBalance + 7e18, ALLOWED_DELTA);

        // sanity checks
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 0);
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward2, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward2, false), 0);
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 0);
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward2, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward2, false), 0);
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0);
        assertEq(stakingDistributor.earnedReward(address(0), stakingRewarded, reward2, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward2, false), 0);
        assertEq(stakingDistributor.enabledRewards(PARTICIPANT_1, stakingRewarded).length, 0);
        assertEq(trackingDistributor.enabledRewards(PARTICIPANT_1, trackingRewarded).length, 0);
        assertEq(stakingDistributor.enabledRewards(PARTICIPANT_2, stakingRewarded)[0], reward2);
        assertEq(trackingDistributor.enabledRewards(PARTICIPANT_2, trackingRewarded)[0], reward2);
        assertEq(stakingDistributor.balanceOf(PARTICIPANT_1, stakingRewarded), 2e18);
        assertEq(stakingDistributor.balanceOf(PARTICIPANT_2, stakingRewarded), 1e18);
        assertEq(trackingDistributor.balanceOf(PARTICIPANT_1, trackingRewarded), 2e18);
        assertEq(trackingDistributor.balanceOf(PARTICIPANT_2, trackingRewarded), 1e18);
        assertEq(stakingDistributor.totalRewardedEligible(stakingRewarded, reward), 0);
        assertEq(trackingDistributor.totalRewardedEligible(trackingRewarded, reward), 0);
        assertEq(stakingDistributor.totalRewardedEligible(stakingRewarded, reward2), 1e18);
        assertEq(trackingDistributor.totalRewardedEligible(trackingRewarded, reward2), 1e18);
        assertEq(stakingDistributor.totalRewardRegistered(stakingRewarded, reward), 19e18);
        assertEq(trackingDistributor.totalRewardRegistered(trackingRewarded, reward), 19e18);
        assertEq(stakingDistributor.totalRewardRegistered(stakingRewarded, reward2), 19e18);
        assertEq(trackingDistributor.totalRewardRegistered(trackingRewarded, reward2), 19e18);
        assertApproxEqRel(stakingDistributor.totalRewardClaimed(stakingRewarded, reward), 19e18, ALLOWED_DELTA);
        assertApproxEqRel(trackingDistributor.totalRewardClaimed(trackingRewarded, reward), 19e18, ALLOWED_DELTA);
        assertApproxEqRel(stakingDistributor.totalRewardClaimed(stakingRewarded, reward2), 19e18, ALLOWED_DELTA);
        assertApproxEqRel(trackingDistributor.totalRewardClaimed(trackingRewarded, reward2), 19e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_1), 2 * 6.083334e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward2).balanceOf(PARTICIPANT_1), 2 * 3.5e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_2), 2 * 6.916667e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward2).balanceOf(PARTICIPANT_2), 2 * 8.5e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward).balanceOf(address(this)), 2 * 6e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward2).balanceOf(address(this)), 2 * 7e18, ALLOWED_DELTA);
    }

    // single rewarded and single reward; multiple participants who don't earn all the time (hence address(0) earns
    // some rewards)
    function test_Scenario_6(uint48 blockTimestamp) external {
        blockTimestamp = uint48(bound(blockTimestamp, 1, type(uint48).max - 365 days));

        uint256 ALLOWED_DELTA = 1e12; // 0.0001%

        // mint the tracking rewarded token to address(1) as a placeholder address, allow participants to spend it
        vm.startPrank(address(1));
        MockERC20(trackingRewarded).mint(address(1), 10e18);
        MockERC20(trackingRewarded).approve(PARTICIPANT_1, type(uint256).max);
        MockERC20(trackingRewarded).approve(PARTICIPANT_2, type(uint256).max);
        MockERC20(trackingRewarded).approve(PARTICIPANT_3, type(uint256).max);
        vm.stopPrank();

        // mint the tokens to the participants
        vm.startPrank(PARTICIPANT_1);
        MockERC20(stakingRewarded).mint(PARTICIPANT_1, 10e18);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_2);
        MockERC20(stakingRewarded).mint(PARTICIPANT_2, 10e18);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_3);
        MockERC20(stakingRewarded).mint(PARTICIPANT_3, 10e18);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);
        vm.stopPrank();

        vm.warp(blockTimestamp);

        // prepare the amounts; 3 epochs
        uint128[] memory amounts = new uint128[](3);
        amounts[0] = 5e18;
        amounts[1] = 10e18;
        amounts[2] = 20e18;

        // register the distribution schemes in both distributors
        vm.startPrank(seeder);
        stakingDistributor.registerReward(stakingRewarded, reward, 0, amounts);
        trackingDistributor.registerReward(trackingRewarded, reward, 0, amounts);
        vm.stopPrank();

        // forward the time to the start of the distribution scheme + 1 day
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1) + 1 days);

        // participant 1: enables reward and increases eligible balance
        // participant 2: enables reward and increases eligible balance
        // participant 3: does nothing
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.enableReward(stakingRewarded, reward);
        stakingDistributor.stake(stakingRewarded, 1e18);

        MockERC20(trackingRewarded).transferFrom(address(1), PARTICIPANT_1, 1e18);
        MockERC20BalanceForwarder(trackingRewarded).enableBalanceForwarding();
        trackingDistributor.enableReward(trackingRewarded, reward);
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_2);
        stakingDistributor.stake(stakingRewarded, 4e18);
        stakingDistributor.enableReward(stakingRewarded, reward);

        trackingDistributor.enableReward(trackingRewarded, reward);
        MockERC20BalanceForwarder(trackingRewarded).enableBalanceForwarding();
        MockERC20(trackingRewarded).transferFrom(address(1), PARTICIPANT_2, 4e18);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 14 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 1.9e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 1.9e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 7.6e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 7.6e18, ALLOWED_DELTA
        );
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_3, stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_3, trackingRewarded, reward, false), 0);
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0.5e18, ALLOWED_DELTA
        );

        // participant 3: enables reward and increases eligible balance
        vm.startPrank(PARTICIPANT_3);
        stakingDistributor.enableReward(stakingRewarded, reward);
        stakingDistributor.stake(stakingRewarded, 5e18);

        trackingDistributor.enableReward(trackingRewarded, reward);
        MockERC20(trackingRewarded).transferFrom(address(1), PARTICIPANT_3, 5e18);
        MockERC20BalanceForwarder(trackingRewarded).enableBalanceForwarding();
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 2.4e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 2.4e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 9.6e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 9.6e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_3, stakingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_3, trackingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0.5e18, ALLOWED_DELTA
        );

        // checkpoint the rewards, each participant updates the data for themselves
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.updateReward(stakingRewarded, reward, address(0));
        trackingDistributor.updateReward(trackingRewarded, reward, address(0));
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_2);
        stakingDistributor.updateReward(stakingRewarded, reward, address(0));
        trackingDistributor.updateReward(trackingRewarded, reward, address(0));
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_3);
        stakingDistributor.updateReward(stakingRewarded, reward, address(0));
        trackingDistributor.updateReward(trackingRewarded, reward, address(0));
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // participant 3: disables and forfeits the reward
        vm.startPrank(PARTICIPANT_3);
        stakingDistributor.unstake(stakingRewarded, 5e18, PARTICIPANT_3, true);
        trackingDistributor.disableReward(trackingRewarded, reward, true);
        vm.stopPrank();

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 4.4e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 4.4e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 17.6e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 17.6e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_3, stakingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_3, trackingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0.5e18, ALLOWED_DELTA
        );

        // checkpoint the rewards, each participate updates the data for themselves
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.updateReward(stakingRewarded, reward, address(0));
        trackingDistributor.updateReward(trackingRewarded, reward, address(0));
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_2);
        stakingDistributor.updateReward(stakingRewarded, reward, address(0));
        trackingDistributor.updateReward(trackingRewarded, reward, address(0));
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_3);
        stakingDistributor.updateReward(stakingRewarded, reward, address(0));
        trackingDistributor.updateReward(trackingRewarded, reward, address(0));
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 25 days);

        // participant 1: claims their rewards forgiving the most recent ones
        vm.startPrank(PARTICIPANT_1);
        uint256 preRewardBalance = MockERC20(reward).balanceOf(PARTICIPANT_1);
        stakingDistributor.claimReward(stakingRewarded, reward, PARTICIPANT_1, true);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_1), preRewardBalance + 4.4e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward).balanceOf(PARTICIPANT_1);
        trackingDistributor.claimReward(trackingRewarded, reward, PARTICIPANT_1, true);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_1), preRewardBalance + 4.4e18, ALLOWED_DELTA);
        vm.stopPrank();

        // participant 2: claims their rewards forgiving the most recent ones and gets rid of the eligible balance
        vm.startPrank(PARTICIPANT_2);
        preRewardBalance = MockERC20(reward).balanceOf(PARTICIPANT_2);
        stakingDistributor.claimReward(stakingRewarded, reward, PARTICIPANT_2, true);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_2), preRewardBalance + 17.6e18, ALLOWED_DELTA);

        preRewardBalance = MockERC20(reward).balanceOf(PARTICIPANT_2);
        trackingDistributor.claimReward(trackingRewarded, reward, PARTICIPANT_2, true);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_2), preRewardBalance + 17.6e18, ALLOWED_DELTA);

        stakingDistributor.unstake(stakingRewarded, 4e18, PARTICIPANT_2, true);
        trackingDistributor.disableReward(trackingRewarded, reward, true);
        vm.stopPrank();

        // verify earnings
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 10e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 10e18, ALLOWED_DELTA
        );
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_2, stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 0);
        assertApproxEqRel(
            stakingDistributor.earnedReward(PARTICIPANT_3, stakingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_3, trackingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            stakingDistributor.earnedReward(address(0), stakingRewarded, reward, false), 0.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0.5e18, ALLOWED_DELTA
        );

        // sanity checks
        assertEq(stakingDistributor.enabledRewards(PARTICIPANT_1, stakingRewarded)[0], reward);
        assertEq(trackingDistributor.enabledRewards(PARTICIPANT_1, trackingRewarded)[0], reward);
        assertEq(stakingDistributor.enabledRewards(PARTICIPANT_2, stakingRewarded)[0], reward);
        assertEq(trackingDistributor.enabledRewards(PARTICIPANT_2, trackingRewarded).length, 0);
        assertEq(stakingDistributor.enabledRewards(PARTICIPANT_3, stakingRewarded)[0], reward);
        assertEq(trackingDistributor.enabledRewards(PARTICIPANT_3, trackingRewarded).length, 0);
        assertEq(stakingDistributor.balanceOf(PARTICIPANT_1, stakingRewarded), 1e18);
        assertEq(stakingDistributor.balanceOf(PARTICIPANT_2, stakingRewarded), 0);
        assertEq(stakingDistributor.balanceOf(PARTICIPANT_3, stakingRewarded), 0);
        assertEq(trackingDistributor.balanceOf(PARTICIPANT_1, trackingRewarded), 1e18);
        assertEq(trackingDistributor.balanceOf(PARTICIPANT_2, trackingRewarded), 4e18);
        assertEq(trackingDistributor.balanceOf(PARTICIPANT_3, trackingRewarded), 5e18);
        assertEq(stakingDistributor.totalRewardedEligible(stakingRewarded, reward), 1e18);
        assertEq(trackingDistributor.totalRewardedEligible(trackingRewarded, reward), 1e18);
        assertEq(stakingDistributor.totalRewardRegistered(stakingRewarded, reward), 35e18);
        assertEq(trackingDistributor.totalRewardRegistered(trackingRewarded, reward), 35e18);
        assertApproxEqRel(stakingDistributor.totalRewardClaimed(stakingRewarded, reward), 22e18, ALLOWED_DELTA);
        assertApproxEqRel(trackingDistributor.totalRewardClaimed(trackingRewarded, reward), 22e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_1), 2 * 4.4e18, ALLOWED_DELTA);
        assertApproxEqRel(MockERC20(reward).balanceOf(PARTICIPANT_2), 2 * 17.6e18, ALLOWED_DELTA);
        assertEq(MockERC20(reward).balanceOf(PARTICIPANT_3), 0);
    }

    // balance tracker hook test
    function test_Scenario_7(uint48 blockTimestamp) external {
        blockTimestamp = uint48(bound(blockTimestamp, 1, type(uint48).max - 365 days));

        uint256 ALLOWED_DELTA = 1e12; // 0.0001%

        // mint the tracking rewarded token to participant 1
        MockERC20(trackingRewarded).mint(PARTICIPANT_1, 10e18);

        vm.warp(blockTimestamp);

        // prepare the amounts; 5 epochs
        uint128[] memory amounts = new uint128[](5);
        amounts[0] = 10e18;
        amounts[1] = 10e18;
        amounts[2] = 10e18;
        amounts[3] = 10e18;
        amounts[4] = 10e18;

        // register the distribution scheme
        vm.startPrank(seeder);
        trackingDistributor.registerReward(trackingRewarded, reward, 0, amounts);
        vm.stopPrank();

        // all participants enable reward and balance forwarding but only participant 1 has eligible balance at this
        // point
        vm.startPrank(PARTICIPANT_1);
        MockERC20BalanceForwarder(trackingRewarded).enableBalanceForwarding();
        trackingDistributor.enableReward(trackingRewarded, reward);
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_2);
        MockERC20BalanceForwarder(trackingRewarded).enableBalanceForwarding();
        trackingDistributor.enableReward(trackingRewarded, reward);
        vm.stopPrank();

        vm.startPrank(PARTICIPANT_3);
        MockERC20BalanceForwarder(trackingRewarded).enableBalanceForwarding();
        trackingDistributor.enableReward(trackingRewarded, reward);
        vm.stopPrank();

        // forward the time to the middle of the second epoch of the distribution scheme
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1) + 15 days);

        // verify earnings
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 15e18, ALLOWED_DELTA
        );
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_3, trackingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0);

        // participant 1 transfers tokens to participant 2
        vm.prank(PARTICIPANT_1);
        MockERC20(trackingRewarded).transfer(PARTICIPANT_2, 5e18);

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 17.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_3, trackingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0);

        // participant 2 transfers tokens to participant 3
        vm.prank(PARTICIPANT_2);
        MockERC20(trackingRewarded).transfer(PARTICIPANT_3, 5e18);

        // forward the time
        vm.warp(block.timestamp + 10 days);

        // verify earnings
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 22.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_3, trackingRewarded, reward, false), 5e18, ALLOWED_DELTA
        );
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0);

        // participant 3 gets all the tokens
        vm.prank(PARTICIPANT_1);
        MockERC20(trackingRewarded).transfer(PARTICIPANT_3, 5e18);

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 22.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 2.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_3, trackingRewarded, reward, false), 10e18, ALLOWED_DELTA
        );
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0);

        // participant 3 transfers all tokens to participant 2
        vm.prank(PARTICIPANT_3);
        MockERC20(trackingRewarded).transfer(PARTICIPANT_2, 10e18);

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 22.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 7.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_3, trackingRewarded, reward, false), 10e18, ALLOWED_DELTA
        );
        assertEq(trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 0);

        // participant 2 transfers all tokens to an address that doesn't have the balance tracker enabled (i.e.
        // trackingRewarded contract)
        vm.prank(PARTICIPANT_2);
        MockERC20(trackingRewarded).transfer(trackingRewarded, 10e18);

        // forward the time
        vm.warp(block.timestamp + 5 days);

        // verify earnings
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 22.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 7.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_3, trackingRewarded, reward, false), 10e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 5e18, ALLOWED_DELTA
        );

        // trackingRewarded transfers the tokens to participant 1 and participant 3
        vm.prank(trackingRewarded);
        MockERC20(trackingRewarded).transfer(PARTICIPANT_1, 2e18);

        vm.prank(trackingRewarded);
        MockERC20(trackingRewarded).transfer(PARTICIPANT_3, 8e18);

        // forward the time
        vm.warp(block.timestamp + 10 days);

        // verify earnings
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 23.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_2, trackingRewarded, reward, false), 7.5e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(PARTICIPANT_3, trackingRewarded, reward, false), 14e18, ALLOWED_DELTA
        );
        assertApproxEqRel(
            trackingDistributor.earnedReward(address(0), trackingRewarded, reward, false), 5e18, ALLOWED_DELTA
        );
    }

    // staking/unstaking within the same block
    function test_Scenario_8(uint48 blockTimestamp) external {
        blockTimestamp = uint48(bound(blockTimestamp, 1, type(uint48).max - 365 days));

        // mint the tracking rewarded token to the participant
        MockERC20(stakingRewarded).mint(PARTICIPANT_1, 10e18);
        MockERC20(trackingRewarded).mint(PARTICIPANT_1, 10e18);

        vm.prank(PARTICIPANT_1);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);

        vm.warp(blockTimestamp);

        // prepare the amounts; 1 epoch
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10e18;

        // register the distribution schemes in both distributors
        vm.startPrank(seeder);
        stakingDistributor.registerReward(stakingRewarded, reward, 0, amounts);
        trackingDistributor.registerReward(trackingRewarded, reward, 0, amounts);
        vm.stopPrank();

        // forward the time to the middle of the distribution scheme
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1) + 5 days);

        // enable reward and balance forwarding
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.enableReward(stakingRewarded, reward);
        trackingDistributor.enableReward(trackingRewarded, reward);
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 10);

        // verify earnings
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 0);

        // verify that staking (or enabling balance forwarding) and unstaking (or disabling balance forwarding) within
        // the same block does not earn any rewards
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.stake(stakingRewarded, 10e18);
        MockERC20BalanceForwarder(trackingRewarded).enableBalanceForwarding();

        assertEq(stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 0);

        stakingDistributor.unstake(stakingRewarded, 10e18, PARTICIPANT_1, true);
        MockERC20BalanceForwarder(trackingRewarded).disableBalanceForwarding();

        assertEq(stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, reward, false), 0);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, reward, false), 0);

        // try to claim
        uint256 preBalance = MockERC20(reward).balanceOf(PARTICIPANT_1);
        stakingDistributor.claimReward(stakingRewarded, reward, PARTICIPANT_1, false);
        trackingDistributor.claimReward(trackingRewarded, reward, PARTICIPANT_1, false);
        assertEq(MockERC20(reward).balanceOf(PARTICIPANT_1), preBalance);
        vm.stopPrank();
    }

    // reward and rewarded are the same
    function test_Scenario_9(uint48 blockTimestamp) external {
        blockTimestamp = uint48(bound(blockTimestamp, 1, type(uint48).max - 365 days));

        // mint the tokens
        MockERC20(stakingRewarded).mint(seeder, 100e18);
        MockERC20(stakingRewarded).mint(PARTICIPANT_1, 100e18);
        MockERC20(trackingRewarded).mint(seeder, 100e18);
        MockERC20(trackingRewarded).mint(PARTICIPANT_1, 100e18);

        vm.prank(seeder);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);

        vm.prank(seeder);
        MockERC20(trackingRewarded).approve(address(trackingDistributor), type(uint256).max);

        vm.prank(PARTICIPANT_1);
        MockERC20(stakingRewarded).approve(address(stakingDistributor), type(uint256).max);

        vm.warp(blockTimestamp);

        // prepare the amounts; 1 epoch
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 10e18;

        // register the distribution schemes in both distributors
        vm.startPrank(seeder);
        stakingDistributor.registerReward(stakingRewarded, stakingRewarded, 0, amounts);
        trackingDistributor.registerReward(trackingRewarded, trackingRewarded, 0, amounts);
        vm.stopPrank();

        // forward the time to the beginning of the distribution scheme
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1));

        // enable reward and balance forwarding, stake
        vm.startPrank(PARTICIPANT_1);
        stakingDistributor.enableReward(stakingRewarded, stakingRewarded);
        trackingDistributor.enableReward(trackingRewarded, trackingRewarded);
        stakingDistributor.stake(stakingRewarded, 1e18);
        MockERC20BalanceForwarder(trackingRewarded).enableBalanceForwarding();
        vm.stopPrank();

        // forward the time
        vm.warp(block.timestamp + 10 days);

        // verify earnings
        assertEq(stakingDistributor.earnedReward(PARTICIPANT_1, stakingRewarded, stakingRewarded, false), 10e18);
        assertEq(trackingDistributor.earnedReward(PARTICIPANT_1, trackingRewarded, trackingRewarded, false), 10e18);

        // claim and unstake
        vm.startPrank(PARTICIPANT_1);
        uint256 preBalance = MockERC20(stakingRewarded).balanceOf(PARTICIPANT_1);
        stakingDistributor.claimReward(stakingRewarded, stakingRewarded, PARTICIPANT_1, false);
        stakingDistributor.unstake(stakingRewarded, 1e18, PARTICIPANT_1, true);
        assertEq(MockERC20(stakingRewarded).balanceOf(PARTICIPANT_1), preBalance + 11e18);

        preBalance = MockERC20(trackingRewarded).balanceOf(PARTICIPANT_1);
        stakingDistributor.claimReward(trackingRewarded, trackingRewarded, PARTICIPANT_1, false);
        assertEq(MockERC20(stakingRewarded).balanceOf(PARTICIPANT_1), preBalance + 10e18);
    }

    function test_Scenario_Liquidation(uint48 blockTimestamp) external {
        blockTimestamp = uint48(bound(blockTimestamp, 1, type(uint48).max - 365 days));

        address[] memory rewards = new address[](5);
        for (uint256 i = 0; i < rewards.length; i++) {
            rewards[i] = address(new MockERC20("Reward", "RWD"));

            MockERC20(rewards[i]).mint(seeder, 100e18);

            vm.prank(seeder);
            MockERC20(rewards[i]).approve(address(trackingDistributor), type(uint256).max);
        }

        // mint the tokens
        MockERC20(trackingRewarded).mint(PARTICIPANT_1, 100e18);

        vm.warp(blockTimestamp);

        // prepare the amounts; 5 epochs
        uint128[] memory amounts = new uint128[](5);
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = 1e18;
        }

        // register the distribution scheme
        vm.startPrank(seeder);
        for (uint256 i = 0; i < rewards.length; i++) {
            trackingDistributor.registerReward(trackingRewarded, rewards[i], 0, amounts);
        }
        vm.stopPrank();

        // forward the time to the beginning of the distribution scheme
        vm.warp(stakingDistributor.getEpochStartTimestamp(stakingDistributor.currentEpoch() + 1));

        // enable reward and balance forwarding, stake
        vm.startPrank(PARTICIPANT_1);
        for (uint256 i = 0; i < rewards.length; i++) {
            trackingDistributor.enableReward(trackingRewarded, rewards[i]);
        }
        MockERC20BalanceForwarder(trackingRewarded).enableBalanceForwarding();

        // for coverage
        vm.expectRevert(BaseRewardStreams.TooManyRewardsEnabled.selector);
        trackingDistributor.enableReward(trackingRewarded, reward);

        // deploy mock controller
        address controller = address(new MockController(evc));

        // enable collateral
        evc.enableCollateral(PARTICIPANT_1, trackingRewarded);

        // enable controller
        evc.enableController(PARTICIPANT_1, controller);

        // forward the time
        vm.warp(block.timestamp + 50 days);

        // controller liquidates
        uint256 preBalance = MockERC20(trackingRewarded).balanceOf(PARTICIPANT_1);
        MockController(controller).liquidateCollateralShares(trackingRewarded, PARTICIPANT_1, trackingRewarded, 10e18);
        assertEq(MockERC20(trackingRewarded).balanceOf(PARTICIPANT_1), preBalance - 10e18);
    }

    function test_AssertionTrigger(
        address _account,
        address _rewarded,
        address _reward,
        uint96 totalRegistered,
        uint96 totalClaimed,
        uint96 claimable
    ) external {
        vm.assume(_account != address(0));
        totalRegistered = uint96(bound(totalRegistered, 0, type(uint96).max - 1));
        totalClaimed = uint96(bound(totalClaimed, 0, totalRegistered));
        claimable = uint96(bound(claimable, totalRegistered - totalClaimed + 1, type(uint96).max));

        BaseRewardStreams.EarnStorage memory earnStorage =
            BaseRewardStreams.EarnStorage({claimable: claimable, accumulator: 0});

        stakingDistributor.setDistributionTotals(_rewarded, _reward, 0, totalRegistered, totalClaimed);
        trackingDistributor.setDistributionTotals(_rewarded, _reward, 0, totalRegistered, totalClaimed);

        stakingDistributor.setAccountEarnedData(_account, _rewarded, _reward, earnStorage);
        trackingDistributor.setAccountEarnedData(_account, _rewarded, _reward, earnStorage);

        vm.prank(_account);
        vm.expectRevert();
        stakingDistributor.claimReward(_rewarded, _reward, _account, true);

        vm.prank(_account);
        vm.expectRevert();
        trackingDistributor.claimReward(_rewarded, _reward, _account, true);
    }

    function test_RevertWhenRecipientInvalid_Claim(
        address _rewarded,
        address _reward,
        address _receiver,
        bool _forfeitRecentReward
    ) external {
        _rewarded = boundAddr(_rewarded);
        _reward = boundAddr(_reward);
        _receiver = boundAddr(_receiver);
        vm.assume(uint160(_receiver) > 256);

        vm.etch(_reward, address(reward).code);
        MockERC20(_reward).mint(address(stakingDistributor), 100e18);
        MockERC20(_reward).mint(address(trackingDistributor), 100e18);
        stakingDistributor.setDistributionTotals(_rewarded, _reward, 0, 100e18, 0);
        trackingDistributor.setDistributionTotals(_rewarded, _reward, 0, 100e18, 0);

        stakingDistributor.setAccountEarnedData(address(this), _rewarded, _reward, BaseRewardStreams.EarnStorage(1, 0));
        vm.expectRevert(BaseRewardStreams.InvalidRecipient.selector);
        stakingDistributor.claimReward(_rewarded, _reward, address(0), _forfeitRecentReward);
        stakingDistributor.claimReward(_rewarded, _reward, _receiver, _forfeitRecentReward);

        trackingDistributor.setAccountEarnedData(address(this), _rewarded, _reward, BaseRewardStreams.EarnStorage(1, 0));
        vm.expectRevert(BaseRewardStreams.InvalidRecipient.selector);
        trackingDistributor.claimReward(_rewarded, _reward, address(0), _forfeitRecentReward);
        trackingDistributor.claimReward(_rewarded, _reward, _receiver, _forfeitRecentReward);

        // register the receiver as the owner on the EVC
        assertEq(evc.getAccountOwner(_receiver), address(0));
        vm.prank(_receiver);
        evc.call(address(0), _receiver, 0, "");
        assertEq(evc.getAccountOwner(_receiver), _receiver);

        for (uint160 i = 0; i < 256; ++i) {
            address __receiver = address(uint160(_receiver) ^ i);

            // if known non-owner is the recipient, revert
            stakingDistributor.setAccountEarnedData(
                address(this), _rewarded, _reward, BaseRewardStreams.EarnStorage(1, 0)
            );
            if (i != 0) vm.expectRevert(BaseRewardStreams.InvalidRecipient.selector);
            stakingDistributor.claimReward(_rewarded, _reward, __receiver, _forfeitRecentReward);

            trackingDistributor.setAccountEarnedData(
                address(this), _rewarded, _reward, BaseRewardStreams.EarnStorage(1, 0)
            );
            if (i != 0) vm.expectRevert(BaseRewardStreams.InvalidRecipient.selector);
            trackingDistributor.claimReward(_rewarded, _reward, __receiver, _forfeitRecentReward);

            stakingDistributor.setAccountEarnedData(address(0), _rewarded, _reward, BaseRewardStreams.EarnStorage(1, 0));
            if (i != 0) vm.expectRevert(BaseRewardStreams.InvalidRecipient.selector);
            stakingDistributor.updateReward(_rewarded, _reward, __receiver);

            trackingDistributor.setAccountEarnedData(
                address(0), _rewarded, _reward, BaseRewardStreams.EarnStorage(1, 0)
            );
            if (i != 0) vm.expectRevert(BaseRewardStreams.InvalidRecipient.selector);
            trackingDistributor.updateReward(_rewarded, _reward, __receiver);
        }
    }
}
