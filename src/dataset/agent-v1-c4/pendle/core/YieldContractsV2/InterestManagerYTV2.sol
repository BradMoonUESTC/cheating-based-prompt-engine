// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../interfaces/IPYieldToken.sol";
import "../../interfaces/IPPrincipalToken.sol";
import "../../interfaces/IPInterestManagerYTV2.sol";
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
abstract contract InterestManagerYTV2 is TokenHelper, IPInterestManagerYTV2 {
    using PMath for uint256;

    struct UserInterest {
        uint128 index;
        uint128 accrued;
        uint256 pyIndex;
    }

    uint256 public lastInterestBlock;

    uint256 public globalInterestIndex;

    mapping(address => UserInterest) public userInterest;

    uint256 internal constant INITIAL_INTEREST_INDEX = 1;

    function _updateAndDistributeInterest(address user) internal virtual {
        _updateAndDistributeInterestForTwo(user, address(0));
    }

    function _updateAndDistributeInterestForTwo(address user1, address user2) internal virtual {
        (uint256 index, uint256 pyIndex) = _updateInterestIndex();

        if (user1 != address(0) && user1 != address(this)) _distributeInterestPrivate(user1, index, pyIndex);
        if (user2 != address(0) && user2 != address(this)) _distributeInterestPrivate(user2, index, pyIndex);
    }

    function _doTransferOutInterest(address user, address SY) internal returns (uint256 interestAmount) {
        interestAmount = userInterest[user].accrued;
        userInterest[user].accrued = 0;
        _transferOut(SY, user, interestAmount);
    }

    // should only be callable from `_distributeInterestForTwo` & make sure user != address(0) && user != address(this)
    function _distributeInterestPrivate(address user, uint256 currentIndex, uint256 pyIndex) private {
        assert(user != address(0) && user != address(this));

        uint256 prevIndex = userInterest[user].index;
        // uint256 interestFeeRate = _getInterestFeeRate();

        if (prevIndex == currentIndex) return;

        if (prevIndex == 0) {
            userInterest[user].index = currentIndex.Uint128();
            userInterest[user].pyIndex = pyIndex;
            return;
        }

        userInterest[user].accrued += _YTbalance(user).mulDown(currentIndex - prevIndex).Uint128();
        userInterest[user].index = currentIndex.Uint128();
        userInterest[user].pyIndex = pyIndex;
    }

    function _updateInterestIndex() internal returns (uint256 index, uint256 pyIndex) {
        if (lastInterestBlock != block.number) {
            // if we have not yet update the index for this block
            lastInterestBlock = block.number;

            uint256 totalShares = _YTSupply();
            uint256 accrued;

            (accrued, pyIndex) = _collectInterest();
            index = globalInterestIndex;

            if (index == 0) index = INITIAL_INTEREST_INDEX;
            if (totalShares != 0) index += accrued.divDown(totalShares);

            globalInterestIndex = index;
        } else {
            index = globalInterestIndex;
            pyIndex = _getGlobalPYIndex();
        }
    }

    function _getGlobalPYIndex() internal view virtual returns (uint256);

    function _collectInterest() internal virtual returns (uint256, uint256);

    function _YTbalance(address user) internal view virtual returns (uint256);

    function _YTSupply() internal view virtual returns (uint256);
}
