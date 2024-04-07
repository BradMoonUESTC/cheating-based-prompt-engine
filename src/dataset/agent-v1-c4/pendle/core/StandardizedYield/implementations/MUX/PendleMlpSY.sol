// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../../SYBaseWithRewards.sol";
import "../../../../interfaces/MUX/IMUXRewardRouter.sol";
import "../../../../interfaces/IPPriceFeed.sol";
import "../../../libraries/ArrayLib.sol";

contract PendleMlpSY is SYBaseWithRewards {
    using PMath for uint256;

    uint256 constant VEMUX_MAXTIME = 4 * 365 * 86400; // 4 years

    address public immutable mlp;
    address public immutable sMlp;
    address public immutable mux;
    address public immutable weth;
    address public immutable arb;
    address public immutable rewardRouter;

    // reward status
    bool public hasVeMuxPosition;
    bool public isRewardSettled;

    // non-security related
    address public immutable mlpPriceFeed;

    constructor(
        address _rewardRouter,
        address _mlpPriceFeed,
        address _arb
    ) SYBaseWithRewards("SY MUXLP", "SY-MUXLP", IMUXRewardRouter(_rewardRouter).mlp()) {
        rewardRouter = _rewardRouter;
        weth = IMUXRewardRouter(_rewardRouter).weth();
        mlp = IMUXRewardRouter(_rewardRouter).mlp();
        sMlp = IMUXRewardRouter(_rewardRouter).mlpMuxTracker();
        mux = IMUXRewardRouter(_rewardRouter).mux();
        arb = _arb;

        mlpPriceFeed = _mlpPriceFeed;

        // Dont have to approve for mlpMuxTracker as the contract allows whitelisted handlers
        // to transfer from anyone (MUX's reward router in this case)
        _safeApproveInf(mlp, IMUXRewardRouter(_rewardRouter).mlpFeeTracker());
        _safeApproveInf(mux, IMUXRewardRouter(_rewardRouter).votingEscrow());
        _safeApproveInf(mux, IMUXRewardRouter(_rewardRouter).muxVester());
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    function _deposit(
        address /*tokenIn*/,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 /*amountSharesOut*/) {
        IMUXRewardRouter(rewardRouter).stakeMlp(amountDeposited);
        return amountDeposited;
    }

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 /*amountTokenOut*/) {
        IMUXRewardRouter(rewardRouter).unstakeMlp(amountSharesToRedeem);
        _transferOut(tokenOut, receiver, amountSharesToRedeem);
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
    function _getRewardTokens() internal view override returns (address[] memory) {
        return ArrayLib.create(weth, arb);
    }

    function _redeemExternalReward() internal override {
        // IMUXRewardRouter(rewardRouter).compound() would revert in the case mux to be compounded = 0 (2 txns in the same block)
        // So we should not use that method
        IMUXRewardRouter(rewardRouter).claimAll();

        bool _hasVeMuxPosition = hasVeMuxPosition;
        bool _isRewardSettled = isRewardSettled;

        if (_isRewardSettled) return;

        uint256 muxBalance = _selfBalance(mux);
        if (muxBalance > 0) {
            IMUXRewardRouter(rewardRouter).stakeMux(muxBalance, block.timestamp + VEMUX_MAXTIME);
            if (!_hasVeMuxPosition) {
                hasVeMuxPosition = true;
            }
        } else if (_hasVeMuxPosition) {
            IMUXRewardRouter(rewardRouter).increaseStakeUnlockTime(block.timestamp + VEMUX_MAXTIME);
        }
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address,
        uint256 amountTokenToDeposit
    ) internal pure override returns (uint256 /*amountSharesOut*/) {
        return amountTokenToDeposit;
    }

    function _previewRedeem(
        address,
        uint256 amountSharesToRedeem
    ) internal pure override returns (uint256 /*amountTokenOut*/) {
        return amountSharesToRedeem;
    }

    function getTokensIn() public view virtual override returns (address[] memory) {
        return ArrayLib.create(mlp);
    }

    function getTokensOut() public view virtual override returns (address[] memory) {
        return ArrayLib.create(mlp);
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == mlp;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == mlp;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.LIQUIDITY, mlp, IERC20Metadata(mlp).decimals());
    }

    /*///////////////////////////////////////////////////////////////
                        GOVERNANCE WITHDRAWAL
    //////////////////////////////////////////////////////////////*/

    function setRewardStatus(bool _isRewardSettled) external onlyOwner {
        isRewardSettled = _isRewardSettled;
    }

    /**
     * @dev this function assumes revert if the lock hasnt expired
     * @dev There are two methods for vesting MUX (one through veMUX culmulative reward and one through paired staked MLP)
     *
     * Will not go with the later one as this contract should not utilize users' sMLP for other purposes
     */
    function withdrawAndVestMux() external onlyOwner {
        IMUXRewardRouter(rewardRouter).unstakeMcbAndMux();

        uint256 amountToVest = PMath.min(
            _selfBalance(mux),
            IMUXRewardRouter(rewardRouter).maxVestableTokenFromVe(address(this))
        );
        IMUXRewardRouter(rewardRouter).depositToVeVester(amountToVest);
    }

    function claimVestedRewards(address receiver) external onlyOwner returns (uint256 amountClaimed) {
        IMUXRewardRouter(rewardRouter).claimVestedTokenFromVe(address(this));

        address mcb = IMUXRewardRouter(rewardRouter).mcb();
        amountClaimed = _selfBalance(mcb);
        if (amountClaimed != 0) {
            _transferOut(mcb, receiver, amountClaimed);
        }
    }

    /*///////////////////////////////////////////////////////////////
                        OFF-CHAIN USAGE ONLY
            (NO SECURITY RELATED && CAN BE LEFT UNAUDITED)
    //////////////////////////////////////////////////////////////*/

    function getPrice() external view returns (uint256) {
        return IPPriceFeed(mlpPriceFeed).getPrice();
    }
}
