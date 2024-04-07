// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/IStandardizedYield.sol";
import "../../interfaces/IPYieldToken.sol";
import "../../interfaces/IPPrincipalToken.sol";

import "../libraries/math/PMath.sol";
import "../libraries/ArrayLib.sol";
import "../../interfaces/IPYieldContractFactory.sol";
import "../StandardizedYield/SYUtils.sol";
import "../libraries/Errors.sol";
import "../libraries/MiniHelpers.sol";

import "../RewardManager/RewardManagerAbstract.sol";
import "../erc20/PendleERC20.sol";
import "./InterestManagerYT.sol";

/**
Invariance to maintain:
- address(0) & address(this) should never have any rewards & activeBalance accounting done. This is
    guaranteed by address(0) & address(this) check in each updateForTwo function
*/
contract PendleYieldToken is IPYieldToken, PendleERC20, RewardManagerAbstract, InterestManagerYT {
    using PMath for uint256;
    using SafeERC20 for IERC20;
    using ArrayLib for uint256[];

    struct PostExpiryData {
        uint128 firstPYIndex;
        uint128 totalSyInterestForTreasury;
        mapping(address => uint256) firstRewardIndex;
        mapping(address => uint256) userRewardOwed;
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
            _distributeInterest(user);
            interestOut = _doTransferOutInterest(user, SY, factory);
            emit RedeemInterest(user, interestOut);
        } else {
            interestOut = 0;
        }
    }

    /**
     * @dev All rewards and interests accrued post-expiry goes to the treasury.
     * Reverts if called pre-expiry.
     */
    function redeemInterestAndRewardsPostExpiryForTreasury()
        external
        nonReentrant
        updateData
        returns (uint256 interestOut, uint256[] memory rewardsOut)
    {
        if (!isExpired()) revert Errors.YCNotExpired();

        address treasury = IPYieldContractFactory(factory).treasury();

        address[] memory tokens = getRewardTokens();
        rewardsOut = new uint256[](tokens.length);

        _redeemExternalReward();

        for (uint256 i = 0; i < tokens.length; i++) {
            rewardsOut[i] = _selfBalance(tokens[i]) - postExpiry.userRewardOwed[tokens[i]];
            emit CollectRewardFee(tokens[i], rewardsOut[i]);
        }

        _transferOut(tokens, treasury, rewardsOut);

        interestOut = postExpiry.totalSyInterestForTreasury;
        postExpiry.totalSyInterestForTreasury = 0;
        _transferOut(SY, treasury, interestOut);

        emit CollectInterestFee(interestOut);
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
     * @return totalSyInterestForTreasury current amount of SY interests post-expiry for treasury
     * @return firstRewardIndexes the earliest reward indices post-expiry, for each reward token
     * @return userRewardOwed amount of unclaimed user rewards, for each reward token
     */
    function getPostExpiryData()
        external
        view
        returns (
            uint256 firstPYIndex,
            uint256 totalSyInterestForTreasury,
            uint256[] memory firstRewardIndexes,
            uint256[] memory userRewardOwed
        )
    {
        if (postExpiry.firstPYIndex == 0) revert Errors.YCPostExpiryDataNotSet();

        firstPYIndex = postExpiry.firstPYIndex;
        totalSyInterestForTreasury = postExpiry.totalSyInterestForTreasury;

        address[] memory tokens = getRewardTokens();
        firstRewardIndexes = new uint256[](tokens.length);
        userRewardOwed = new uint256[](tokens.length);

        for (uint256 i = 0; i < tokens.length; ++i) {
            firstRewardIndexes[i] = postExpiry.firstRewardIndex[tokens[i]];
            userRewardOwed[i] = postExpiry.userRewardOwed[tokens[i]];
        }
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
        if (totalSyInterestPostExpiry != 0) {
            postExpiry.totalSyInterestForTreasury += totalSyInterestPostExpiry.Uint128();
        }
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

        _redeemExternalReward(); // do a final redeem. All the future reward income will belong to the treasury

        local.firstPYIndex = _pyIndexCurrent().Uint128();
        address[] memory rewardTokens = IStandardizedYield(SY).getRewardTokens();
        uint256[] memory rewardIndexes = IStandardizedYield(SY).rewardIndexesCurrent();
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            local.firstRewardIndex[rewardTokens[i]] = rewardIndexes[i];
            local.userRewardOwed[rewardTokens[i]] = _selfBalance(rewardTokens[i]);
        }
    }

    /*///////////////////////////////////////////////////////////////
                               INTEREST-RELATED
    //////////////////////////////////////////////////////////////*/

    function _getInterestIndex() internal virtual override returns (uint256 index) {
        if (isExpired()) index = postExpiry.firstPYIndex;
        else index = _pyIndexCurrent();
    }

    function _pyIndexCurrent() internal returns (uint256 currentIndex) {
        if (doCacheIndexSameBlock && pyIndexLastUpdatedBlock == block.number) return _pyIndexStored;

        uint128 index128 = PMath.max(IStandardizedYield(SY).exchangeRate(), _pyIndexStored).Uint128();

        currentIndex = index128;
        _pyIndexStored = index128;
        pyIndexLastUpdatedBlock = uint128(block.number);

        emit NewInterestIndex(currentIndex);
    }

    function _YTbalance(address user) internal view override returns (uint256) {
        return balanceOf(user);
    }

    /*///////////////////////////////////////////////////////////////
                               REWARDS-RELATED
    //////////////////////////////////////////////////////////////*/

    function getRewardTokens() public view returns (address[] memory) {
        return IStandardizedYield(SY).getRewardTokens();
    }

    function _doTransferOutRewards(
        address user,
        address receiver
    ) internal virtual override returns (uint256[] memory rewardAmounts) {
        address[] memory tokens = getRewardTokens();

        if (isExpired()) {
            // post-expiry, all incoming rewards will go to the treasury
            // hence, we can save users one _redeemExternal here
            for (uint256 i = 0; i < tokens.length; i++)
                postExpiry.userRewardOwed[tokens[i]] -= userReward[tokens[i]][user].accrued;
            rewardAmounts = __doTransferOutRewardsLocal(tokens, user, receiver, false);
        } else {
            rewardAmounts = __doTransferOutRewardsLocal(tokens, user, receiver, true);
        }
    }

    function __doTransferOutRewardsLocal(
        address[] memory tokens,
        address user,
        address receiver,
        bool allowedToRedeemExternalReward
    ) internal returns (uint256[] memory rewardAmounts) {
        address treasury = IPYieldContractFactory(factory).treasury();
        uint256 feeRate = IPYieldContractFactory(factory).rewardFeeRate();
        bool redeemExternalThisRound;

        rewardAmounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 rewardPreFee = userReward[tokens[i]][user].accrued;
            userReward[tokens[i]][user].accrued = 0;

            uint256 feeAmount = rewardPreFee.mulDown(feeRate);
            rewardAmounts[i] = rewardPreFee - feeAmount;

            if (!redeemExternalThisRound && allowedToRedeemExternalReward) {
                if (_selfBalance(tokens[i]) < rewardPreFee) {
                    _redeemExternalReward();
                    redeemExternalThisRound = true;
                }
            }

            _transferOut(tokens[i], treasury, feeAmount);
            _transferOut(tokens[i], receiver, rewardAmounts[i]);

            emit CollectRewardFee(tokens[i], feeAmount);
        }
    }

    function _redeemExternalReward() internal virtual override {
        IStandardizedYield(SY).claimRewards(address(this));
    }

    /// @dev effectively returning the amount of SY generating rewards for this user
    function _rewardSharesUser(address user) internal view virtual override returns (uint256) {
        uint256 index = userInterest[user].index;
        if (index == 0) return 0;
        return SYUtils.assetToSy(index, balanceOf(user)) + userInterest[user].accrued;
    }

    function _updateRewardIndex() internal override returns (address[] memory tokens, uint256[] memory indexes) {
        tokens = getRewardTokens();
        if (isExpired()) {
            indexes = new uint256[](tokens.length);
            for (uint256 i = 0; i < tokens.length; i++) indexes[i] = postExpiry.firstRewardIndex[tokens[i]];
        } else {
            indexes = IStandardizedYield(SY).rewardIndexesCurrent();
        }
    }

    //solhint-disable-next-line ordering
    function _beforeTokenTransfer(address from, address to, uint256) internal override {
        if (isExpired()) _setPostExpiryData();
        _updateAndDistributeRewardsForTwo(from, to);
        _distributeInterestForTwo(from, to);
    }
}
