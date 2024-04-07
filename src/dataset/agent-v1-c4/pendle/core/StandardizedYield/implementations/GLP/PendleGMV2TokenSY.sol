// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../../../interfaces/IPPriceFeed.sol";
import "../../../../interfaces/IPLinearDistributor.sol";
import "../../SYBaseWithRewards.sol";
import "../../../libraries/ArrayLib.sol";
import "./GMTokenPricingHelper.sol";

contract PendleGMV2TokenSY is SYBaseWithRewards, IPPriceFeed {
    using ArrayLib for address[];

    address public immutable gm;
    address public immutable arb;
    address public immutable linearDistributor;
    address public immutable pricingHelper;

    constructor(
        string memory _name,
        string memory _symbol,
        address _gm,
        address _arb,
        address _linearDistributor,
        address _pricingHelper
    ) SYBaseWithRewards(_name, _symbol, _gm) {
        gm = _gm;
        arb = _arb;
        linearDistributor = _linearDistributor;
        pricingHelper = _pricingHelper;

        _safeApproveInf(_arb, _linearDistributor);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {SYBase-_deposit}
     */
    function _deposit(
        address /*tokenIn*/,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        return amountDeposited;
    }

    /**
     * @dev See {SYBase-_redeem}
     */
    function _redeem(
        address receiver,
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 /*amountTokenOut*/) {
        _transferOut(gm, receiver, amountSharesToRedeem);
        return amountSharesToRedeem;
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    function exchangeRate() public view virtual override returns (uint256) {
        return PMath.ONE;
    }

    /*///////////////////////////////////////////////////////////////
                               REWARDS-RELATED
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IStandardizedYield-getRewardTokens}
     */
    function _getRewardTokens() internal view override returns (address[] memory res) {
        return ArrayLib.create(arb);
    }

    function _redeemExternalReward() internal override {
        uint256 amountToVest = _getFloatingArbReward();
        if (amountToVest > 0) {
            IPLinearDistributor(linearDistributor).queueVestAndClaim(arb, amountToVest);
        } else {
            IPLinearDistributor(linearDistributor).claim(arb);
        }
    }

    function _getFloatingArbReward() internal view returns (uint256) {
        RewardState memory state = rewardState[arb];
        return _selfBalance(arb) - state.lastBalance;
    }

    /*///////////////////////////////////////////////////////////////
                    MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address /*tokenIn*/,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 /*amountSharesOut*/) {
        return amountTokenToDeposit;
    }

    function _previewRedeem(
        address /*tokenOut*/,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 /*amountTokenOut*/) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view virtual override returns (address[] memory) {
        return ArrayLib.create(gm);
    }

    function getTokensOut() public view virtual override returns (address[] memory) {
        return ArrayLib.create(gm);
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == gm;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == gm;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.LIQUIDITY, gm, IERC20Metadata(gm).decimals());
    }

    function getPrice() external view returns (uint256) {
        return GMTokenPricingHelper(pricingHelper).getPrice(gm);
    }
}
