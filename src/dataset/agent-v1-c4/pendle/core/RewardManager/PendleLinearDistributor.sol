// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "../libraries/BoringOwnableUpgradeable.sol";
import "../libraries/TokenHelper.sol";
import "../libraries/math/PMath.sol";
import "../../interfaces/IPLinearDistributor.sol";

contract PendleLinearDistributor is UUPSUpgradeable, AccessControlUpgradeable, TokenHelper, IPLinearDistributor {
    using PMath for uint128;
    using PMath for uint192;
    using PMath for uint256;

    bytes32 public constant MAINTAINER = keccak256("MAINTAINER");

    mapping(address => bool) internal isWhitelisted;

    // [token, addr] => distribution
    mapping(address => mapping(address => DistributionData)) public distributionDatas;

    constructor() {
        _disableInitializers();
    }

    modifier onlyWhitelisted() {
        require(isWhitelisted[msg.sender], "not whitelisted");
        _;
    }

    function isMaintainer(address addr) public view returns (bool) {
        return (hasRole(DEFAULT_ADMIN_ROLE, addr) || hasRole(MAINTAINER, addr));
    }

    modifier onlyMaintainer() {
        require(isMaintainer(msg.sender), "not maintainer");
        _;
    }

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "not admin");
        _;
    }

    // ----------------- core-logic ----------------------

    function queueVestAndClaim(address token, uint256 amountVestToQueue) external onlyWhitelisted returns (uint256) {
        require(amountVestToQueue > 0, "invalid amountVestToQueue");

        uint256 amountOut = _getClaimableRewardAndUpdate(token, msg.sender, amountVestToQueue);

        // dodging extreme case of amountOut = amountVestToQueue
        if (amountOut > amountVestToQueue) {
            _transferOut(token, msg.sender, amountOut - amountVestToQueue);
        } else if (amountVestToQueue > amountOut) {
            _transferIn(token, msg.sender, amountVestToQueue - amountOut);
        }

        emit VestQueued(token, msg.sender, amountVestToQueue);
        emit Claim(token, msg.sender, amountOut);

        return amountOut;
    }

    function claim(address token) external returns (uint256) {
        uint256 amountOut = _getClaimableRewardAndUpdate(token, msg.sender, 0);
        if (amountOut > 0) {
            _transferOut(token, msg.sender, amountOut);
        }
        emit Claim(token, msg.sender, amountOut);
        return amountOut;
    }

    function applyVestRewards(
        address[] memory tokens,
        address[] memory addrs,
        uint256[] memory durations
    ) external onlyMaintainer {
        require(tokens.length == addrs.length, "invalid array length");
        require(tokens.length == durations.length, "invalid array length");

        for (uint256 i = 0; i < tokens.length; ++i) {
            _applyVestReward(tokens[i], addrs[i], durations[i]);
        }
    }

    function _applyVestReward(address token, address addr, uint256 duration) internal {
        DistributionData memory data = _updateRewardView(token, addr);

        uint256 amountVesting = data.unvestedReward;
        if (amountVesting == 0) {
            return;
        }

        uint256 leftOver = data.rewardPerSec.mulDown((data.endTime - PMath.min(block.timestamp, data.endTime)));
        uint256 undistrbutedReward = amountVesting + leftOver;

        data.unvestedReward = 0;
        data.endTime = (block.timestamp + duration).Uint32();
        data.rewardPerSec = undistrbutedReward.divDown(duration).Uint192();
        distributionDatas[token][addr] = data;

        emit Vested(token, addr, amountVesting, duration);
    }

    // data.lastDistributedTime is guaranteed to be block.timestamp after calling this
    function _getClaimableRewardAndUpdate(
        address token,
        address addr,
        uint256 amountVestToQueue
    ) internal returns (uint256 amountOut) {
        DistributionData memory data = _updateRewardView(token, addr);
        amountOut = data.accruedReward;

        data.accruedReward = 0;
        data.unvestedReward += amountVestToQueue.Uint128();

        distributionDatas[token][addr] = data;
    }

    function _updateRewardView(address token, address addr) internal view returns (DistributionData memory data) {
        data = distributionDatas[token][addr];
        uint256 distributeFrom = PMath.min(data.lastDistributedTime, data.endTime);
        uint256 distributeTo = PMath.min(block.timestamp, data.endTime);
        data.accruedReward += data.rewardPerSec.mulDown(distributeTo - distributeFrom).Uint128();
        data.lastDistributedTime = block.timestamp.Uint32();
    }

    // ----------------- governance-related --------------

    function setWhitelisted(address addr, bool status) external onlyAdmin {
        isWhitelisted[addr] = status;
    }

    function initialize() external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // ----------------- upgrade-related -----------------

    function _authorizeUpgrade(address) internal override onlyAdmin {}
}
