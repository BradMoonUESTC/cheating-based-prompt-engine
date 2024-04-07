// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../interfaces/IPYieldToken.sol";
import "../../interfaces/IPPrincipalToken.sol";
import "../../interfaces/IPInterestManagerYT.sol";
import "../../interfaces/IPYieldContractFactory.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../libraries/math/PMath.sol";
import "../libraries/TokenHelper.sol";
import "../StandardizedYield/SYUtils.sol";

/*
With YT yielding more SYs overtime, which is allowed to be redeemed by users, the reward distribution should
be based on the amount of SYs that their YT currently represent, plus with their dueInterest.

It has been proven and tested that totalSyRedeemable will not change over time, unless users redeem their interest or redeemPY.

Due to this, it is required to update users' accruedReward STRICTLY BEFORE redeeming their interest.
*/
abstract contract InterestManagerYT is TokenHelper, IPInterestManagerYT {
    using PMath for uint256;

    struct UserInterest {
        uint128 index;
        uint128 accrued;
    }

    mapping(address => UserInterest) public userInterest;

    function _distributeInterest(address user) internal {
        _distributeInterestForTwo(user, address(0));
    }

    function _distributeInterestForTwo(address user1, address user2) internal {
        uint256 index = _getInterestIndex();
        if (user1 != address(0) && user1 != address(this)) _distributeInterestPrivate(user1, index);
        if (user2 != address(0) && user2 != address(this)) _distributeInterestPrivate(user2, index);
    }

    function _doTransferOutInterest(
        address user,
        address SY,
        address factory
    ) internal returns (uint256 interestAmount) {
        address treasury = IPYieldContractFactory(factory).treasury();
        uint256 feeRate = IPYieldContractFactory(factory).interestFeeRate();

        uint256 interestPreFee = userInterest[user].accrued;
        userInterest[user].accrued = 0;

        uint256 feeAmount = interestPreFee.mulDown(feeRate);
        interestAmount = interestPreFee - feeAmount;

        _transferOut(SY, treasury, feeAmount);
        _transferOut(SY, user, interestAmount);

        emit CollectInterestFee(feeAmount);
    }

    // should only be callable from `_distributeInterestForTwo` & make sure user != address(0) && user != address(this)
    function _distributeInterestPrivate(address user, uint256 currentIndex) private {
        assert(user != address(0) && user != address(this));

        uint256 prevIndex = userInterest[user].index;

        if (prevIndex == currentIndex) return;
        if (prevIndex == 0) {
            userInterest[user].index = currentIndex.Uint128();
            return;
        }

        uint256 principal = _YTbalance(user);

        uint256 interestFromYT = (principal * (currentIndex - prevIndex)).divDown(prevIndex * currentIndex);

        userInterest[user].accrued += interestFromYT.Uint128();
        userInterest[user].index = currentIndex.Uint128();
    }

    function _getInterestIndex() internal virtual returns (uint256 index);

    function _YTbalance(address user) internal view virtual returns (uint256);
}
