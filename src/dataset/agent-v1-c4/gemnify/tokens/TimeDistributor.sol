// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IDistributor} from "./interfaces/IDistributor.sol";

contract TimeDistributor is IDistributor {
    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant DISTRIBUTION_INTERVAL = 1 hours;
    address public gov;
    address public admin;

    mapping(address => address) public rewardTokens;
    mapping(address => uint256) public override tokensPerInterval;
    mapping(address => uint256) public lastDistributionTime;

    event Distribute(address receiver, uint256 amount);
    event DistributionChange(
        address receiver,
        uint256 amount,
        address rewardToken
    );
    event TokensPerIntervalChange(address receiver, uint256 amount);

    modifier onlyGov() {
        require(msg.sender == gov, "TimeDistributor: forbidden");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "TimeDistributor: forbidden");
        _;
    }

    constructor() {
        gov = msg.sender;
        admin = msg.sender;
    }

    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }

    function setTokensPerInterval(
        address _receiver,
        uint256 _amount
    ) external onlyAdmin {
        if (lastDistributionTime[_receiver] != 0) {
            uint256 intervals = getIntervals(_receiver);
            require(intervals == 0, "TimeDistributor: pending distribution");
        }

        tokensPerInterval[_receiver] = _amount;
        _updateLastDistributionTime(_receiver);
        emit TokensPerIntervalChange(_receiver, _amount);
    }

    function updateLastDistributionTime(address _receiver) external onlyAdmin {
        _updateLastDistributionTime(_receiver);
    }

    function setDistribution(
        address[] calldata _receivers,
        uint256[] calldata _amounts,
        address[] calldata _rewardTokens
    ) external onlyGov {
        for (uint256 i = 0; i < _receivers.length; i++) {
            address receiver = _receivers[i];

            if (lastDistributionTime[receiver] != 0) {
                uint256 intervals = getIntervals(receiver);
                require(
                    intervals == 0,
                    "TimeDistributor: pending distribution"
                );
            }

            uint256 amount = _amounts[i];
            address rewardToken = _rewardTokens[i];
            tokensPerInterval[receiver] = amount;
            rewardTokens[receiver] = rewardToken;
            _updateLastDistributionTime(receiver);
            emit DistributionChange(receiver, amount, rewardToken);
        }
    }

    function distribute() external override returns (uint256) {
        address receiver = msg.sender;
        uint256 intervals = getIntervals(receiver);

        if (intervals == 0) {
            return 0;
        }

        uint256 amount = getDistributionAmount(receiver);
        _updateLastDistributionTime(receiver);

        if (amount == 0) {
            return 0;
        }

        IERC20(rewardTokens[receiver]).safeTransfer(receiver, amount);

        emit Distribute(receiver, amount);
        return amount;
    }

    function getRewardToken(
        address _receiver
    ) external view override returns (address) {
        return rewardTokens[_receiver];
    }

    function getDistributionAmount(
        address _receiver
    ) public view override returns (uint256) {
        uint256 _tokensPerInterval = tokensPerInterval[_receiver];
        if (_tokensPerInterval == 0) {
            return 0;
        }

        uint256 intervals = getIntervals(_receiver);
        uint256 amount = _tokensPerInterval * intervals;

        if (IERC20(rewardTokens[_receiver]).balanceOf(address(this)) < amount) {
            return 0;
        }

        return amount;
    }

    function getIntervals(address _receiver) public view returns (uint256) {
        uint256 timeDiff = block.timestamp - lastDistributionTime[_receiver];
        return timeDiff / DISTRIBUTION_INTERVAL;
    }

    function _updateLastDistributionTime(address _receiver) private {
        lastDistributionTime[_receiver] =
            (block.timestamp / DISTRIBUTION_INTERVAL) *
            DISTRIBUTION_INTERVAL;
    }
}
