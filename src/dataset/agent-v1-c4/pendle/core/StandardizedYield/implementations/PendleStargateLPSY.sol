// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "../SYBaseWithRewards.sol";
import "../../../interfaces/IStargateRouter.sol";
import "../../../interfaces/IStargateLP.sol";
import "../../../interfaces/IStargateStaking.sol";

contract PendleStargateLPSY is SYBaseWithRewards {
    uint256 public constant STARGATE_BP_DENOMINATOR = 10000;

    using PMath for uint256;

    uint16 public immutable pid; // pool id
    uint256 public immutable sid; // staking id
    address public immutable lp;
    address public immutable underlying;
    address public immutable stargateRouter;
    address public immutable stargateStaking;
    address public immutable stgToken;

    // preview variables
    uint256 public immutable convertRate;

    constructor(
        string memory _name,
        string memory _symbol,
        address _stargateLP,
        address _stargateStaking,
        uint256 _sid
    ) SYBaseWithRewards(_name, _symbol, _stargateLP) {
        lp = _stargateLP;
        underlying = IStargateLP(lp).token();

        stargateRouter = IStargateLP(lp).router();
        pid = uint16(IStargateLP(lp).poolId());

        stargateStaking = _stargateStaking;
        sid = _sid;

        stgToken = IStargateStaking(stargateStaking).stargate();

        // preview variables
        convertRate = IStargateLP(lp).convertRate();

        _safeApproveInf(underlying, stargateRouter);
        _safeApproveInf(lp, stargateStaking);

        _validateStargateStakingId(stargateStaking, sid, lp);
    }

    function _validateStargateStakingId(address staking, uint256 id, address lpToken) internal view {
        (address _lpToken, , , ) = IStargateStaking(staking).poolInfo(id);
        // Custom error not needed here since this only happens on deployment
        require(_lpToken == lpToken, "invalid sid & lpToken");
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    /**
     * The underlying yield token is startgateLP. If the base token deposited is underlying, the function
     * deposits received underlying into the startgateLP contract.
     */
    function _deposit(
        address tokenIn,
        uint256 amountDeposited
    ) internal virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == underlying) {
            IStargateRouter(stargateRouter).addLiquidity(pid, amountDeposited, address(this));
            amountSharesOut = _selfBalance(lp);
            // all outstanding LP will be staked
        } else {
            amountSharesOut = amountDeposited;
        }
        IStargateStaking(stargateStaking).deposit(sid, amountSharesOut);
    }

    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 amountTokenOut) {
        IStargateStaking(stargateStaking).withdraw(sid, amountSharesToRedeem);
        if (tokenOut == lp) {
            amountTokenOut = amountSharesToRedeem;
            _transferOut(lp, receiver, amountTokenOut);
        } else {
            /**
             * @dev There is an lp cap variable in stargate to define the maximum amount of lp
             * which can be burned.
             * In case there is not enough liquidity in the pool to proceed the withdrawal,
             * stargatePool will not revert and try to withdraw as much lp as it can instead.
             *
             * When this rare case happens, Pendle's SY should guarantee to revert.
             */

            uint256 preBalanceLp = _selfBalance(lp);

            uint256 amountSD = IStargateRouter(stargateRouter).instantRedeemLocal(pid, amountSharesToRedeem, receiver);
            uint256 lpUsed = preBalanceLp - _selfBalance(lp);
            if (lpUsed < amountSharesToRedeem) {
                revert Errors.SYStargateRedeemCapExceeded(amountSharesToRedeem, lpUsed);
            }

            amountTokenOut = amountSD * convertRate;
        }
    }

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates and updates the exchange rate of shares to underlying asset token
     * @dev It is the exchange rate of lp to underlying
     */
    function exchangeRate() public view virtual override returns (uint256) {
        return IStargateLP(lp).totalLiquidity().divDown(IStargateLP(lp).totalSupply()) * convertRate;
    }

    /*///////////////////////////////////////////////////////////////
                               REWARDS-RELATED
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IStandardizedYield-getRewardTokens}
     */
    function _getRewardTokens() internal view override returns (address[] memory res) {
        res = new address[](1);
        res[0] = stgToken;
    }

    function _redeemExternalReward() internal override {
        IStargateStaking(stargateStaking).withdraw(sid, 0);
    }

    /*///////////////////////////////////////////////////////////////
                MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view override returns (uint256 amountSharesOut) {
        if (tokenIn == lp) {
            amountSharesOut = amountTokenToDeposit;
        } else {
            uint256 totalLiquidity = IStargateLP(lp).totalLiquidity();
            uint256 totalSupply = IStargateLP(lp).totalSupply();
            uint256 mintFeeBP = IStargateLP(lp).mintFeeBP();

            uint256 amountSD = amountTokenToDeposit / convertRate;

            // Tho fee is always enabled, it is currently set to zero
            uint256 mintFeeSD = (amountSD * mintFeeBP) / STARGATE_BP_DENOMINATOR;
            amountSD = amountSD - mintFeeSD;

            // skip check for lp.totalSupply() == 0
            amountSharesOut = (amountSD * totalSupply) / totalLiquidity;
        }
    }

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view override returns (uint256 amountTokenOut) {
        if (tokenOut == lp) {
            amountTokenOut = amountSharesToRedeem;
        } else {
            uint256 totalLiquidity = IStargateLP(lp).totalLiquidity();
            uint256 totalSupply = IStargateLP(lp).totalSupply();
            uint256 deltaCredit = IStargateLP(lp).deltaCredit();

            uint256 capAmountLp = (deltaCredit * totalSupply) / totalLiquidity;
            if (amountSharesToRedeem > capAmountLp) {
                revert Errors.SYStargateRedeemCapExceeded(amountSharesToRedeem, capAmountLp);
            }

            uint256 amountSD = (amountSharesToRedeem * totalLiquidity) / totalSupply;
            amountTokenOut = amountSD * convertRate;
        }
    }

    function getTokensIn() public view virtual override returns (address[] memory res) {
        res = new address[](2);
        res[0] = underlying;
        res[1] = lp;
    }

    function getTokensOut() public view virtual override returns (address[] memory res) {
        res = new address[](2);
        res[0] = underlying;
        res[1] = lp;
    }

    function isValidTokenIn(address token) public view virtual override returns (bool) {
        return token == underlying || token == lp;
    }

    function isValidTokenOut(address token) public view virtual override returns (bool) {
        return token == underlying || token == lp;
    }

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.TOKEN, underlying, IERC20Metadata(underlying).decimals());
    }
}
