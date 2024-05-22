// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {EthereumVaultConnector} from "evc/EthereumVaultConnector.sol";
import {StakingRewardStreams} from "../../src/StakingRewardStreams.sol";
import {TrackingRewardStreams} from "../../src/TrackingRewardStreams.sol";
import {MockERC20, MockERC20BalanceForwarder} from "../utils/MockERC20.sol";

contract POC_Test is Test {
    EthereumVaultConnector internal evc;
    StakingRewardStreams internal stakingDistributor;
    TrackingRewardStreams internal trackingDistributor;
    MockERC20 internal mockERC20;
    MockERC20BalanceForwarder internal mockERC20BalanceForwarder;

    function setUp() external {
        evc = new EthereumVaultConnector();

        stakingDistributor = new StakingRewardStreams(address(evc), 10 days);
        mockERC20 = new MockERC20("Mock ERC20", "MOCK");

        trackingDistributor = new TrackingRewardStreams(address(evc), 10 days);
        mockERC20BalanceForwarder = new MockERC20BalanceForwarder(evc, trackingDistributor, "Mock ERC20 BT", "MOCK_BT");
    }

    function test_POC() external {}
}
