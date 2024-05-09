// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IPriceFeed} from "./interfaces/IPriceFeed.sol";

contract PriceFeed is IPriceFeed {
    int256 public answer;
    uint80 public roundId;
    string public override description = "PriceFeed";
    address public override aggregator;

    uint256 public decimals;
    address public owner;

    mapping(uint80 => int256) public answers;
    mapping(address => bool) public isAdmin;

    modifier onlyOwner() {
        require(msg.sender == owner, "PriceFeed: forbidden");
        _;
    }

    constructor() {
        owner = msg.sender;
        isAdmin[msg.sender] = true;
    }

    function setAdmin(address _account, bool _isAdmin) public onlyOwner {
        isAdmin[_account] = _isAdmin;
    }

    function latestAnswer() public view override returns (int256) {
        return answer;
    }

    function latestRound() public view override returns (uint80) {
        return roundId;
    }

    function setLatestAnswer(int256 _answer) public {
        require(isAdmin[msg.sender], "PriceFeed: forbidden");
        roundId = roundId + 1;
        answer = _answer;
        answers[roundId] = _answer;
    }

    // returns roundId, answer, startedAt, updatedAt, answeredInRound
    function getRoundData(
        uint80 _roundId
    ) public view override returns (uint80, int256, uint256, uint256, uint80) {
        return (_roundId, answers[_roundId], 0, 0, 0);
    }
}
