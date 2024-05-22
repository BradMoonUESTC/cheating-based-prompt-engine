// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.23;

contract MockBalanceTracker {
    uint256 public numCalls;
    mapping(address => mapping(uint256 => mapping(bool => uint256))) public calls;
    mapping(address => uint256) public balance;

    struct ReentrantCall {
        address to;
        bytes data;
    }

    ReentrantCall reentrantCall;

    function balanceTrackerHook(address account, uint256 newAccountBalance, bool forfeitRecentReward) external {
        calls[account][newAccountBalance][forfeitRecentReward]++;
        balance[account] = newAccountBalance;
        numCalls++;

        ReentrantCall memory _reentrantCall = reentrantCall;
        if (_reentrantCall.to == address(0)) return;

        reentrantCall = ReentrantCall(address(0), "");

        (bool success, bytes memory result) = address(_reentrantCall.to).call(_reentrantCall.data);
        if (success) return;
        if (result.length == 0) revert();
        assembly {
            revert(add(32, result), mload(result))
        }
    }

    function setReentrantCall(address to, bytes memory data) external {
        reentrantCall.to = to;
        reentrantCall.data = data;
    }
}
