// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "evc/EthereumVaultConnector.sol";
import "../harness/BaseRewardStreamsHarness.sol";
import {MockERC20, MockERC20Malicious} from "../utils/MockERC20.sol";

contract RegisterRewardTest is Test {
    EthereumVaultConnector internal evc;
    BaseRewardStreamsHarness internal distributor;
    mapping(address rewarded => mapping(address reward => mapping(uint256 epoch => uint256 amount))) internal
        distributionAmounts;
    address internal rewarded;
    address internal reward;
    address internal seeder;

    function setUp() external {
        evc = new EthereumVaultConnector();

        distributor = new BaseRewardStreamsHarness(address(evc), 10 days);

        rewarded = address(new MockERC20("Rewarded", "RWDD"));
        vm.label(rewarded, "REWARDED");

        reward = address(new MockERC20("Reward", "RWD"));
        vm.label(reward, "REWARD");

        seeder = vm.addr(0xabcdef);
        vm.label(seeder, "SEEDER");

        MockERC20(reward).mint(seeder, 100e18);

        vm.prank(seeder);
        MockERC20(reward).approve(address(distributor), type(uint256).max);
    }

    function updateDistributionAmounts(
        address _rewarded,
        address _reward,
        uint48 _startEpoch,
        uint128[] memory _amounts
    ) internal {
        for (uint256 i; i < _amounts.length; ++i) {
            distributionAmounts[_rewarded][_reward][_startEpoch + i] += _amounts[i];
        }
    }

    function test_RevertIfInvalidEpochDuration_Constructor(uint48 epochDuration) external {
        if (epochDuration < 7 days || epochDuration > 10 * 7 days) {
            vm.expectRevert(BaseRewardStreams.InvalidEpoch.selector);
        }

        new BaseRewardStreamsHarness(address(1), epochDuration);
    }

    function test_RegisterReward(
        uint48 epochDuration,
        uint48 blockTimestamp,
        uint48 startEpoch,
        uint8 amountsLength0,
        uint8 amountsLength1,
        uint8 amountsLength2,
        uint256 seed
    ) external {
        epochDuration = uint48(bound(epochDuration, 7 days, 10 * 7 days));
        blockTimestamp = uint48(bound(blockTimestamp, 1, type(uint48).max - 50 * epochDuration));
        amountsLength0 = uint8(bound(amountsLength0, 1, 25));
        amountsLength1 = uint8(bound(amountsLength1, 1, 25));
        amountsLength2 = uint8(bound(amountsLength2, 1, 25));

        vm.warp(blockTimestamp);
        distributor = new BaseRewardStreamsHarness(address(evc), epochDuration);

        vm.startPrank(seeder);
        MockERC20(reward).approve(address(distributor), type(uint256).max);

        // ------------------ 1st call ------------------
        // prepare the start epoch
        startEpoch = uint48(
            bound(
                startEpoch, distributor.currentEpoch() + 1, distributor.currentEpoch() + distributor.MAX_EPOCHS_AHEAD()
            )
        );

        // prepare the amounts
        uint128[] memory amounts = new uint128[](amountsLength0);
        uint128 totalAmount = 0;
        for (uint256 i; i < amounts.length; ++i) {
            amounts[i] = uint128(uint256(keccak256(abi.encode(seed, i)))) % 1e18;
            totalAmount += amounts[i];
        }

        vm.expectEmit(true, true, true, true, address(distributor));
        emit BaseRewardStreams.RewardRegistered(seeder, rewarded, reward, startEpoch, amounts);
        distributor.registerReward(rewarded, reward, startEpoch, amounts);

        // verify that the total amount was properly transferred
        assertEq(MockERC20(reward).balanceOf(address(distributor)), totalAmount);

        // verify that the distribution and totals storage were properly initialized
        {
            (
                uint48 lastUpdated,
                uint208 accumulator,
                uint256 totalEligible,
                uint128 totalRegistered,
                uint128 totalClaimed
            ) = distributor.getDistributionData(rewarded, reward);
            assertEq(lastUpdated, block.timestamp);
            assertEq(accumulator, 0);
            assertEq(totalEligible, 0);
            assertEq(totalRegistered, totalAmount);
            assertEq(totalClaimed, 0);
        }

        // verify that the distribution amounts storage was properly updated
        updateDistributionAmounts(rewarded, reward, startEpoch, amounts);

        for (uint48 i; i <= distributor.MAX_EPOCHS_AHEAD(); ++i) {
            assertEq(
                distributor.rewardAmount(rewarded, reward, startEpoch + i),
                distributionAmounts[rewarded][reward][startEpoch + i]
            );
        }

        // ------------------ 2nd call ------------------
        // prepare the start epoch
        startEpoch = 0;

        // prepare the amounts
        seed = uint256(keccak256(abi.encode(seed)));
        amounts = new uint128[](amountsLength1);
        totalAmount = 0;
        for (uint256 i; i < amounts.length; ++i) {
            amounts[i] = uint128(uint256(keccak256(abi.encode(seed, i)))) % 1e18;
            totalAmount += amounts[i];
        }

        uint256 preBalance = MockERC20(reward).balanceOf(address(distributor));
        vm.expectEmit(true, true, true, true, address(distributor));
        emit BaseRewardStreams.RewardRegistered(seeder, rewarded, reward, distributor.currentEpoch() + 1, amounts);
        distributor.registerReward(rewarded, reward, startEpoch, amounts);

        // verify that the total amount was properly transferred
        assertEq(MockERC20(reward).balanceOf(address(distributor)), preBalance + totalAmount);

        // verify that the totals storage was properly updated (no time elapsed)
        {
            (
                uint48 lastUpdated,
                uint208 accumulator,
                uint256 totalEligible,
                uint128 totalRegistered,
                uint128 totalClaimed
            ) = distributor.getDistributionData(rewarded, reward);
            assertEq(lastUpdated, block.timestamp);
            assertEq(accumulator, 0);
            assertEq(totalEligible, 0);
            assertEq(totalRegistered, uint128(preBalance) + totalAmount);
            assertEq(totalClaimed, 0);
        }

        // verify that the distribution amounts storage was properly updated
        startEpoch = distributor.currentEpoch() + 1;
        updateDistributionAmounts(rewarded, reward, startEpoch, amounts);

        for (uint48 i; i <= distributor.MAX_EPOCHS_AHEAD(); ++i) {
            assertEq(
                distributor.rewardAmount(rewarded, reward, startEpoch + i),
                distributionAmounts[rewarded][reward][startEpoch + i]
            );
        }

        // ------------------ 3rd call ------------------
        // elapse some random amount of time
        vm.warp(blockTimestamp + epochDuration * amountsLength0 + amountsLength1 + amountsLength2);

        // prepare the start epoch
        startEpoch = uint48(
            bound(
                startEpoch, distributor.currentEpoch() + 1, distributor.currentEpoch() + distributor.MAX_EPOCHS_AHEAD()
            )
        );

        // prepare the amounts
        seed = uint256(keccak256(abi.encode(seed)));
        amounts = new uint128[](amountsLength2);
        totalAmount = 0;
        for (uint256 i; i < amounts.length; ++i) {
            amounts[i] = uint128(uint256(keccak256(abi.encode(seed, i)))) % 1e18;
            totalAmount += amounts[i];
        }

        preBalance = MockERC20(reward).balanceOf(address(distributor));
        vm.expectEmit(true, true, true, true, address(distributor));
        emit BaseRewardStreams.RewardRegistered(seeder, rewarded, reward, startEpoch, amounts);
        distributor.registerReward(rewarded, reward, startEpoch, amounts);

        // verify that the total amount was properly transferred
        assertEq(MockERC20(reward).balanceOf(address(distributor)), preBalance + totalAmount);

        // verify that the totals storage was properly updated (considering that some has time elapsed)
        {
            (
                uint48 lastUpdated,
                uint208 accumulator,
                uint256 totalEligible,
                uint128 totalRegistered,
                uint128 totalClaimed
            ) = distributor.getDistributionData(rewarded, reward);
            assertEq(lastUpdated, block.timestamp);
            assertEq(accumulator, 0);
            assertEq(totalEligible, 0);
            assertEq(totalRegistered, uint128(preBalance) + totalAmount);
            assertEq(totalClaimed, 0);
        }

        // verify that the distribution amounts storage was properly updated
        updateDistributionAmounts(rewarded, reward, startEpoch, amounts);

        for (uint48 i; i <= distributor.MAX_EPOCHS_AHEAD(); ++i) {
            assertEq(
                distributor.rewardAmount(rewarded, reward, startEpoch + i),
                distributionAmounts[rewarded][reward][startEpoch + i]
            );
        }
    }

    function test_RevertIfInvalidEpoch_RegisterReward(uint48 blockTimestamp) external {
        blockTimestamp = uint48(
            bound(blockTimestamp, distributor.EPOCH_DURATION() + 1, type(uint48).max - distributor.EPOCH_DURATION())
        );
        vm.warp(blockTimestamp);

        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 1;

        vm.startPrank(seeder);
        uint48 startEpoch = distributor.currentEpoch();
        vm.expectRevert(BaseRewardStreams.InvalidEpoch.selector);
        distributor.registerReward(rewarded, reward, startEpoch, amounts);
        vm.stopPrank();

        vm.startPrank(seeder);
        startEpoch = uint48(distributor.currentEpoch() + distributor.MAX_EPOCHS_AHEAD() + 1);
        vm.expectRevert(BaseRewardStreams.InvalidEpoch.selector);
        distributor.registerReward(rewarded, reward, startEpoch, amounts);
        vm.stopPrank();

        // succeeds if the epoch is valid
        vm.startPrank(seeder);
        startEpoch = 0;
        distributor.registerReward(rewarded, reward, startEpoch, amounts);
        vm.stopPrank();

        vm.startPrank(seeder);
        startEpoch = distributor.currentEpoch() + 1;
        distributor.registerReward(rewarded, reward, startEpoch, amounts);
        vm.stopPrank();

        vm.startPrank(seeder);
        startEpoch = uint48(distributor.currentEpoch() + distributor.MAX_EPOCHS_AHEAD());
        distributor.registerReward(rewarded, reward, startEpoch, amounts);
        vm.stopPrank();
    }

    function test_RevertIfInvalidAmounts_RegisterReward(uint8 numberOfEpochs) external {
        uint128[] memory amounts = new uint128[](numberOfEpochs);

        if (amounts.length > distributor.MAX_DISTRIBUTION_LENGTH()) {
            vm.expectRevert(BaseRewardStreams.InvalidDistribution.selector);
            distributor.registerReward(rewarded, reward, 0, amounts);
        } else {
            vm.expectRevert(BaseRewardStreams.InvalidAmount.selector);
            distributor.registerReward(rewarded, reward, 0, amounts);
        }
    }

    function test_RevertIfAccumulatorOverflows_RegisterReward() external {
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 1;

        uint128 maxRegistered = uint128(type(uint160).max / 2e19);

        // initialize the distribution data and set the total registered amount to the max value
        distributor.setDistributionData(rewarded, reward, uint48(1), 0, 0, maxRegistered, 0);

        vm.startPrank(seeder);
        vm.expectRevert(BaseRewardStreams.AccumulatorOverflow.selector);
        distributor.registerReward(rewarded, reward, 0, amounts);
        vm.stopPrank();

        // accumulator doesn't overflow if the total registered amount is less than the max value
        distributor.setDistributionData(rewarded, reward, uint48(1), 0, 0, maxRegistered - 1, 0);

        vm.startPrank(seeder);
        distributor.registerReward(rewarded, reward, 0, amounts);
        vm.stopPrank();
    }

    function test_RevertIfMaliciousToken_RegisterReward(uint16[] calldata _amounts) external {
        vm.assume(_amounts.length > 0 && _amounts.length <= distributor.MAX_DISTRIBUTION_LENGTH() && _amounts[0] > 0);

        uint128[] memory amounts = new uint128[](_amounts.length);
        for (uint256 i; i < amounts.length; ++i) {
            amounts[i] = uint128(_amounts[i]);
        }

        address malicious = address(new MockERC20Malicious("Malicious", "MAL"));
        MockERC20(malicious).mint(seeder, type(uint256).max);

        vm.prank(seeder);
        MockERC20(malicious).approve(address(distributor), type(uint256).max);

        vm.startPrank(seeder);
        vm.expectRevert(BaseRewardStreams.InvalidAmount.selector);
        distributor.registerReward(rewarded, malicious, 0, amounts);
        vm.stopPrank();

        // succeeds if the token is not malicious
        vm.startPrank(seeder);
        distributor.registerReward(rewarded, reward, 0, amounts);
        vm.stopPrank();
    }
}
