// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/IStandardizedYield.sol";
import "../../interfaces/IPYieldTokenV2.sol";
import "../../interfaces/IPPrincipalToken.sol";

import "../libraries/math/PMath.sol";
import "../libraries/ArrayLib.sol";
import "../../interfaces/IPYieldContractFactory.sol";
import "../StandardizedYield/SYUtils.sol";
import "../libraries/Errors.sol";
import "../libraries/MiniHelpers.sol";

import "../RewardManager/RewardManager.sol";
import "../erc20/PendleERC20.sol";
import "./InterestManagerYTV2.sol";

/**
Invariance to maintain:
- address(0) & address(this) should never have any rewards & activeBalance accounting done. This is
    guaranteed by address(0) & address(this) check in each updateForTwo function
*/
contract PendleYieldTokenV2 is IPYieldTokenV2, PendleERC20, RewardManager, InterestManagerYTV2 {
    using PMath for uint256;
    using SafeERC20 for IERC20;
    using ArrayLib for uint256[];

    struct PostExpiryData {
        uint256 firstPYIndex;
    }

    address public immutable SY;
    address public immutable PT;
    address public immutable factory;
    uint256 public immutable expiry;

    bool public immutable doCacheIndexSameBlock;

    uint256 public syReserve;

    uint128 public pyIndexLastUpdatedBlock;
    uint128 internal _pyIndexStored;

    PostExpiryData public postExpiry;

    uint256 internal _lastCollectedInterestIndex;

    modifier updateData() {
        if (isExpired()) _setPostExpiryData();
        _;
        _updateSyReserve();
    }

    modifier notExpired() {
        if (isExpired()) revert Errors.YCExpired();
        _;
    }

    /**
     * @param _doCacheIndexSameBlock if true, the PY index is cached for each block, and thus is
     * constant for all txs within the same block. Otherwise, the PY index is recalculated for
     * every tx.
     */
    constructor(
        address _SY,
        address _PT,
        string memory _name,
        string memory _symbol,
        uint8 __decimals,
        uint256 _expiry,
        bool _doCacheIndexSameBlock
    ) PendleERC20(_name, _symbol, __decimals) {
        SY = _SY;
        PT = _PT;
        expiry = _expiry;
        factory = msg.sender;
        doCacheIndexSameBlock = _doCacheIndexSameBlock;
    }

    /**
     * @notice Tokenize SY into PT + YT of equal qty. Every unit of asset of SY will create 1 PT + 1 YT
     * @dev SY must be transferred to this contract prior to calling
     */
    function mintPY(
        address receiverPT,
        address receiverYT
    ) external nonReentrant notExpired updateData returns (uint256 amountPYOut) {
        address[] memory receiverPTs = new address[](1);
        address[] memory receiverYTs = new address[](1);
        uint256[] memory amountSyToMints = new uint256[](1);

        (receiverPTs[0], receiverYTs[0], amountSyToMints[0]) = (receiverPT, receiverYT, _getFloatingSyAmount());

        uint256[] memory amountPYOuts = _mintPY(receiverPTs, receiverYTs, amountSyToMints);
        amountPYOut = amountPYOuts[0];
    }

    /// @notice Tokenize SY into PT + YT for multiple receivers. See `mintPY()` for more details
    function mintPYMulti(
        address[] calldata receiverPTs,
        address[] calldata receiverYTs,
        uint256[] calldata amountSyToMints
    ) external nonReentrant notExpired updateData returns (uint256[] memory amountPYOuts) {
        uint256 length = receiverPTs.length;

        if (length == 0) revert Errors.ArrayEmpty();
        if (receiverYTs.length != length || amountSyToMints.length != length) revert Errors.ArrayLengthMismatch();

        uint256 totalSyToMint = amountSyToMints.sum();
        if (totalSyToMint > _getFloatingSyAmount())
            revert Errors.YieldContractInsufficientSy(totalSyToMint, _getFloatingSyAmount());

        amountPYOuts = _mintPY(receiverPTs, receiverYTs, amountSyToMints);
    }

    /**
     * @notice converts PT(+YT) tokens into SY, but interests & rewards are not redeemed at the
     * same time
     * @dev PT/YT must be transferred to this contract prior to calling
     */
    function redeemPY(address receiver) external nonReentrant updateData returns (uint256 amountSyOut) {
        address[] memory receivers = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        (receivers[0], amounts[0]) = (receiver, _getAmountPYToRedeem());

        uint256[] memory amountSyOuts;
        amountSyOuts = _redeemPY(receivers, amounts);

        amountSyOut = amountSyOuts[0];
    }

    /**
     * @notice redeems PT(+YT) for multiple users. See `redeemPY()`
     * @dev PT/YT must be transferred to this contract prior to calling
     * @dev fails if unable to redeem the total PY amount in `amountPYToRedeems`
     */
    function redeemPYMulti(
        address[] calldata receivers,
        uint256[] calldata amountPYToRedeems
    ) external nonReentrant updateData returns (uint256[] memory amountSyOuts) {
        if (receivers.length != amountPYToRedeems.length) revert Errors.ArrayLengthMismatch();
        if (receivers.length == 0) revert Errors.ArrayEmpty();
        amountSyOuts = _redeemPY(receivers, amountPYToRedeems);
    }

    /**
     * @notice Redeems interests and rewards for `user`
     * @param redeemInterest will only transfer out interest for user if true
     * @param redeemRewards will only transfer out rewards for user if true
     * @dev With YT yielding interest in the form of SY, which is redeemable by users, the reward
     * distribution should be based on the amount of SYs that their YT currently represent, plus
     * their dueInterest. It has been proven and tested that _rewardSharesUser will not change over
     * time, unless users redeem their dueInterest or redeemPY. Due to this, it is required to
     * update users' accruedReward STRICTLY BEFORE transferring out their interest.
     */
    function redeemDueInterestAndRewards(
        address user,
        bool redeemInterest,
        bool redeemRewards
    ) external nonReentrant updateData returns (uint256 interestOut, uint256[] memory rewardsOut) {
        if (!redeemInterest && !redeemRewards) revert Errors.YCNothingToRedeem();

        // if redeemRewards == true, this line must be here for obvious reason
        // if redeemInterest == true, this line must be here because of the reason above
        _updateAndDistributeRewards(user);

        if (redeemRewards) {
            rewardsOut = _doTransferOutRewards(user, user);
            emit RedeemRewards(user, rewardsOut);
        } else {
            address[] memory tokens = getRewardTokens();
            rewardsOut = new uint256[](tokens.length);
        }

        if (redeemInterest) {
            _updateAndDistributeInterest(user);
            interestOut = _doTransferOutInterest(user, SY);
            emit RedeemInterest(user, interestOut);
        } else {
            interestOut = 0;
        }
    }

    /**
     * @dev All rewards and interests accrued post-expiry goes to the treasury.
     * Reverts if called pre-expiry.
     */
    function redeemInterestAndRewardsPostExpiryForTreasury() external nonReentrant updateData {
        if (!isExpired()) revert Errors.YCNotExpired();

        _collectInterest();
        _redeemExternalReward();
    }

    /// @notice updates and returns the reward indexes
    function rewardIndexesCurrent() external override nonReentrant returns (uint256[] memory) {
        return IStandardizedYield(SY).rewardIndexesCurrent();
    }

    /**
     * @notice updates and returns the current PY index
     * @dev this function maximizes the current PY index with the previous index, guaranteeing
     * non-decreasing PY index
     * @dev if `doCacheIndexSameBlock` is true, PY index only updates at most once per block,
     * and has no state changes on the second call onwards (within the same block).
     * @dev see `pyIndexStored()` for view function for cached value.
     */
    function pyIndexCurrent() public nonReentrant returns (uint256 currentIndex) {
        currentIndex = _pyIndexCurrent();
    }

    /// @notice returns the last-updated PY index
    function pyIndexStored() public view returns (uint256) {
        return _pyIndexStored;
    }

    /**
     * @notice do a final rewards redeeming, and sets post-expiry data
     * @dev has no effect if called pre-expiry
     */
    function setPostExpiryData() external nonReentrant {
        if (isExpired()) {
            _setPostExpiryData();
        }
    }

    /**
     * @notice returns the current data post-expiry, if exists
     * @dev reverts if post-expiry data not set (see `setPostExpiryData()`)
     * @return firstPYIndex the earliest PY index post-expiry
     */
    function getPostExpiryData() external view returns (uint256 firstPYIndex) {
        if (postExpiry.firstPYIndex == 0) revert Errors.YCPostExpiryDataNotSet();
        firstPYIndex = postExpiry.firstPYIndex;
    }

    function _mintPY(
        address[] memory receiverPTs,
        address[] memory receiverYTs,
        uint256[] memory amountSyToMints
    ) internal returns (uint256[] memory amountPYOuts) {
        amountPYOuts = new uint256[](amountSyToMints.length);

        uint256 index = _pyIndexCurrent();

        for (uint256 i = 0; i < amountSyToMints.length; i++) {
            amountPYOuts[i] = _calcPYToMint(amountSyToMints[i], index);

            _mint(receiverYTs[i], amountPYOuts[i]);
            IPPrincipalToken(PT).mintByYT(receiverPTs[i], amountPYOuts[i]);

            emit Mint(msg.sender, receiverPTs[i], receiverYTs[i], amountSyToMints[i], amountPYOuts[i]);
        }
    }

    function isExpired() public view returns (bool) {
        return MiniHelpers.isCurrentlyExpired(expiry);
    }

    function isDistributingInterestAndRewards() public view returns (bool) {
        return postExpiry.firstPYIndex == 0;
    }

    function _redeemPY(
        address[] memory receivers,
        uint256[] memory amountPYToRedeems
    ) internal returns (uint256[] memory amountSyOuts) {
        uint256 totalAmountPYToRedeem = amountPYToRedeems.sum();
        IPPrincipalToken(PT).burnByYT(address(this), totalAmountPYToRedeem);
        if (!isExpired()) _burn(address(this), totalAmountPYToRedeem);

        uint256 index = _pyIndexCurrent();
        uint256 totalSyInterestPostExpiry;
        amountSyOuts = new uint256[](receivers.length);

        for (uint256 i = 0; i < receivers.length; i++) {
            uint256 syInterestPostExpiry;
            (amountSyOuts[i], syInterestPostExpiry) = _calcSyRedeemableFromPY(amountPYToRedeems[i], index);
            _transferOut(SY, receivers[i], amountSyOuts[i]);
            totalSyInterestPostExpiry += syInterestPostExpiry;

            emit Burn(msg.sender, receivers[i], amountPYToRedeems[i], amountSyOuts[i]);
        }

        address treasury = IPYieldContractFactory(factory).treasury();
        _transferOut(SY, treasury, totalSyInterestPostExpiry);
    }

    function _calcPYToMint(uint256 amountSy, uint256 indexCurrent) internal pure returns (uint256 amountPY) {
        // doesn't matter before or after expiry, since mintPY is only allowed before expiry
        return SYUtils.syToAsset(indexCurrent, amountSy);
    }

    function _calcSyRedeemableFromPY(
        uint256 amountPY,
        uint256 indexCurrent
    ) internal view returns (uint256 syToUser, uint256 syInterestPostExpiry) {
        syToUser = SYUtils.assetToSy(indexCurrent, amountPY);
        if (isExpired()) {
            uint256 totalSyRedeemable = SYUtils.assetToSy(postExpiry.firstPYIndex, amountPY);
            syInterestPostExpiry = totalSyRedeemable - syToUser;
        }
    }

    function _getAmountPYToRedeem() internal view returns (uint256) {
        if (!isExpired()) return PMath.min(_selfBalance(PT), balanceOf(address(this)));
        else return _selfBalance(PT);
    }

    function _updateSyReserve() internal virtual {
        syReserve = _selfBalance(SY);
    }

    function _getFloatingSyAmount() internal view returns (uint256 amount) {
        amount = _selfBalance(SY) - syReserve;
        if (amount == 0) revert Errors.YCNoFloatingSy();
    }

    function _setPostExpiryData() internal {
        PostExpiryData storage local = postExpiry;
        if (local.firstPYIndex != 0) return; // already set

        _updateInterestIndex();
        _updateRewardIndex();

        // by setting this, we have finished setting postExpiry data, all income will go to treasury
        local.firstPYIndex = _pyIndexCurrent().Uint128();
    }

    /*///////////////////////////////////////////////////////////////
                               INTEREST-RELATED
    //////////////////////////////////////////////////////////////*/

    function _pyIndexCurrent() internal returns (uint256 currentIndex) {
        if (doCacheIndexSameBlock && pyIndexLastUpdatedBlock == block.number) return _pyIndexStored;

        uint128 index128 = PMath.max(IStandardizedYield(SY).exchangeRate(), _pyIndexStored).Uint128();

        currentIndex = index128;
        _pyIndexStored = index128;
        pyIndexLastUpdatedBlock = uint128(block.number);
    }

    function _collectInterest() internal override returns (uint256 accruedAmount, uint256 currentIndex) {
        uint256 prevIndex = _lastCollectedInterestIndex;
        currentIndex = _pyIndexCurrent();

        if (prevIndex != 0 && prevIndex != currentIndex) {
            // guaranteed feeAmount != 0
            address treasury = IPYieldContractFactory(factory).treasury();
            uint256 interestFeeRate = isDistributingInterestAndRewards()
                ? IPYieldContractFactory(factory).interestFeeRate()
                : PMath.ONE;

            uint256 totalInterest = _calcInterest(totalSupply(), prevIndex, currentIndex);
            uint256 feeAmount = totalInterest.mulDown(interestFeeRate);
            accruedAmount = totalInterest - feeAmount;

            _transferOut(SY, treasury, feeAmount);
            _updateSyReserve();
            emit CollectInterestFee(feeAmount);
        }

        _lastCollectedInterestIndex = currentIndex;
    }

    function _calcInterest(uint256 principal, uint256 prevIndex, uint256 currentIndex) internal pure returns (uint256) {
        return (principal * (currentIndex - prevIndex)).divDown(prevIndex * currentIndex);
    }

    function _YTbalance(address user) internal view override returns (uint256) {
        return balanceOf(user);
    }

    function _YTSupply() internal view override returns (uint256) {
        return totalSupply();
    }

    function _getGlobalPYIndex() internal view virtual override returns (uint256) {
        return _pyIndexStored;
    }

    /*///////////////////////////////////////////////////////////////
                               REWARDS-RELATED
    //////////////////////////////////////////////////////////////*/

    function getRewardTokens() public view returns (address[] memory) {
        return IStandardizedYield(SY).getRewardTokens();
    }

    function _redeemExternalReward() internal virtual override {
        IStandardizedYield(SY).claimRewards(address(this));

        address treasury = IPYieldContractFactory(factory).treasury();
        uint256 rewardFeeRate = isDistributingInterestAndRewards()
            ? IPYieldContractFactory(factory).rewardFeeRate()
            : PMath.ONE;

        address[] memory rewardTokens = getRewardTokens();

        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            uint256 accruedReward = _selfBalance(token) - rewardState[token].lastBalance;

            uint256 amountRewardFee = accruedReward.mulDown(rewardFeeRate);

            _transferOut(token, treasury, amountRewardFee);
            emit CollectRewardFee(token, amountRewardFee);
        }
    }

    /// @dev effectively returning the amount of SY generating rewards for this user
    function _rewardSharesUser(address user) internal view virtual override returns (uint256) {
        uint256 index = userInterest[user].pyIndex;
        if (index == 0) return 0;
        return SYUtils.assetToSy(index, balanceOf(user)) + userInterest[user].accrued;
    }

    function _rewardSharesTotal() internal view virtual override returns (uint256) {
        return syReserve;
    }

    function _getRewardTokens() internal view virtual override returns (address[] memory) {
        return IStandardizedYield(SY).getRewardTokens();
    }

    //solhint-disable-next-line ordering
    function _beforeTokenTransfer(address from, address to, uint256) internal override {
        if (isExpired()) _setPostExpiryData();
        _updateAndDistributeRewardsForTwo(from, to);
        _updateAndDistributeInterestForTwo(from, to);
    }
}
