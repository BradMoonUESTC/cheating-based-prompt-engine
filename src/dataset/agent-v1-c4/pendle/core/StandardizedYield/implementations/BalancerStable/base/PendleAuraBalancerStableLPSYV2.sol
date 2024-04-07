// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../../../../interfaces/Balancer/IVault.sol";
import "../../../../../interfaces/Balancer/IRateProvider.sol";
import "../../../../../interfaces/Balancer/IBasePool.sol";
import "../../../../../interfaces/Balancer/IBalancerStablePreview.sol";
import "../../../../../interfaces/ConvexCurve/IBooster.sol";
import "../../../../../interfaces/ConvexCurve/IRewards.sol";

import "./StablePoolUserData.sol";
import "../../../../libraries/ArrayLib.sol";
import "../../../SYBaseWithRewards.sol";

abstract contract PendleAuraBalancerStableLPSYV2 is SYBaseWithRewards {
    using ArrayLib for address[];

    address internal constant BAL_TOKEN = 0xba100000625a3754423978a60c9317c58a424e3D;
    address internal constant AURA_TOKEN = 0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF;
    address internal constant AURA_BOOSTER = 0xA57b8d98dAE62B26Ec3bcC4a365338157060B234;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    uint256 internal constant DEFAULT_GAS_REENTRANCY_CHECK = 7000;

    address public immutable balLp;
    bytes32 public immutable balPoolId;

    uint256 public immutable auraPid;
    address public immutable auraRewardManager;

    IBalancerStablePreview public immutable previewHelper;

    uint256 public gasForReentrancyCheck;
    address[] public extraRewards;

    constructor(
        string memory _name,
        string memory _symbol,
        address _balLp,
        uint256 _auraPid,
        IBalancerStablePreview _previewHelper
    ) SYBaseWithRewards(_name, _symbol, _balLp) {
        balPoolId = IBasePool(_balLp).getPoolId();
        auraPid = _auraPid;

        (balLp, auraRewardManager) = _getPoolInfo(_auraPid);
        if (balLp != _balLp) revert Errors.SYBalancerInvalidPid();

        _safeApproveInf(_balLp, AURA_BOOSTER);

        address[] memory tokens = _getPoolTokenAddresses();
        for (uint256 i = 0; i < tokens.length; ++i) {
            _safeApproveInf(tokens[i], BALANCER_VAULT);
        }

        previewHelper = _previewHelper;
        gasForReentrancyCheck = DEFAULT_GAS_REENTRANCY_CHECK;
    }

    function _getPoolInfo(uint256 _auraPid) internal view returns (address _auraLp, address _auraRewardManager) {
        if (_auraPid > IBooster(AURA_BOOSTER).poolLength()) revert Errors.SYBalancerInvalidPid();
        (_auraLp, , , _auraRewardManager, , ) = IBooster(AURA_BOOSTER).poolInfo(_auraPid);
    }

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Either wraps LP, or also joins pool using exact tokenIn
     */
    function _deposit(address tokenIn, uint256 amount) internal virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == balLp) {
            amountSharesOut = amount;
        } else {
            amountSharesOut = _depositToBalancer(tokenIn, amount);
        }
        IBooster(AURA_BOOSTER).deposit(auraPid, amountSharesOut, true);
    }

    /**
     * @notice Either unwraps LP, or also exits pool using exact LP for only `tokenOut`
     */
    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual override returns (uint256 amountTokenOut) {
        IRewards(auraRewardManager).withdrawAndUnwrap(amountSharesToRedeem, false);

        if (tokenOut == balLp) {
            amountTokenOut = amountSharesToRedeem;
            _transferOut(tokenOut, receiver, amountTokenOut);
        } else {
            amountTokenOut = _redeemFromBalancer(receiver, tokenOut, amountSharesToRedeem);
        }
    }

    function exchangeRate() external view override returns (uint256) {
        _checkBalancerReadOnlyReentrancy();
        return IRateProvider(balLp).getRate();
    }

    /*
    * The `manageUserBalance` function is a non-view function that includes a reentrancy guard
        in the form of `_require(_status != _ENTERED, Errors.REENTRANCY);`. To prevent
        read-only reentrancy, it's important to ensure that our `manageUserBalance` has enough gas
        to reach this check, so that it can fail if necessary.

    * On the way to the check, there's at most one `COLD_SLOAD` plus miscellaneous decoding &
        require, which we've found through testing to cost no more than 3200 gas. Therefore,
        attaching 7000 gas should guarantee that it's always possible to reach the check.

    * Once we've reached the check, one of two scenarios can occur:
    1. The call doesn't pass the check, and reverts with error `BAL#400` ⇒ `response.length = 100`.
    2. The call passes the check. Then, the call can either:
        a. continue on to set the `status` variable to 2, causing the EVM to revert (since
        the sub-call is a `staticcall`), and `response.length == 0`
        b. run out of gas, which will also lead to a revert with `response.length == 0`
    In both cases, to differentiate between 1 and 2, we check `response.length != 0`. If it's
    true, then it's a read-only reentrancy. Otherwise, we're good (and we can ignore
    differentiating between 2a and 2b).
    */
    function _checkBalancerReadOnlyReentrancy() internal view {
        IVault.UserBalanceOp[] memory noop = new IVault.UserBalanceOp[](0);

        (bool isSuccess, bytes memory response) = BALANCER_VAULT.staticcall{gas: gasForReentrancyCheck}(
            abi.encodeWithSignature("manageUserBalance((uint8,address,uint256,address,address)[])", noop)
        );

        assert(!isSuccess);
        if (response.length != 0) revert Errors.SYBalancerReentrancy();
    }

    function setGasForReentrancyCheck(uint256 newGas) external onlyOwner {
        require(newGas >= DEFAULT_GAS_REENTRANCY_CHECK, "lower than default");
        gasForReentrancyCheck = newGas;
    }

    /*///////////////////////////////////////////////////////////////
                    BALANCER-RELATED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _depositToBalancer(address tokenIn, uint256 amountTokenToDeposit) internal virtual returns (uint256) {
        IVault.JoinPoolRequest memory request = _assembleJoinRequest(tokenIn, amountTokenToDeposit);
        IVault(BALANCER_VAULT).joinPool(balPoolId, address(this), address(this), request);

        // amount shares out = amount LP received
        return _selfBalance(balLp);
    }

    function _assembleJoinRequest(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view virtual returns (IVault.JoinPoolRequest memory request) {
        // max amounts in
        address[] memory assets = _getPoolTokenAddresses();

        uint256 amountsLength = _getBPTIndex() < type(uint256).max ? assets.length - 1 : assets.length;

        uint256[] memory amountsIn = new uint256[](amountsLength);
        uint256[] memory maxAmountsIn = new uint256[](assets.length);

        uint256 index = assets.find(tokenIn);
        uint256 indexSkipBPT = index > _getBPTIndex() ? index - 1 : index;
        maxAmountsIn[index] = amountsIn[indexSkipBPT] = amountTokenToDeposit;

        // encode user data
        StablePoolUserData.JoinKind joinKind = StablePoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT;
        uint256 minimumBPT = 0;

        bytes memory userData = abi.encode(joinKind, amountsIn, minimumBPT);

        // assemble joinpoolrequest
        request = IVault.JoinPoolRequest(assets, maxAmountsIn, userData, false);
    }

    function _redeemFromBalancer(
        address receiver,
        address tokenOut,
        uint256 amountLpToRedeem
    ) internal virtual returns (uint256) {
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(receiver);

        IVault.ExitPoolRequest memory request = _assembleExitRequest(tokenOut, amountLpToRedeem);
        IVault(BALANCER_VAULT).exitPool(balPoolId, address(this), payable(receiver), request);

        // calculate amount of tokens out
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(receiver);
        return balanceAfter - balanceBefore;
    }

    function _assembleExitRequest(
        address tokenOut,
        uint256 amountLpToRedeem
    ) internal view virtual returns (IVault.ExitPoolRequest memory request) {
        address[] memory assets = _getPoolTokenAddresses();
        uint256[] memory minAmountsOut = new uint256[](assets.length);

        // encode user data
        StablePoolUserData.ExitKind exitKind = StablePoolUserData.ExitKind.EXACT_BPT_IN_FOR_ONE_TOKEN_OUT;
        uint256 bptAmountIn = amountLpToRedeem;
        uint256 exitTokenIndex = assets.find(tokenOut);

        // must drop BPT index as well
        exitTokenIndex = _getBPTIndex() < exitTokenIndex ? exitTokenIndex - 1 : exitTokenIndex;

        bytes memory userData = abi.encode(exitKind, bptAmountIn, exitTokenIndex);

        // assemble exitpoolrequest
        request = IVault.ExitPoolRequest(assets, minAmountsOut, userData, false);
    }

    /// @dev this should return tokens in the same order as `IVault.getPoolTokens()`
    function _getPoolTokenAddresses() internal view virtual returns (address[] memory res);

    /// @dev should be overriden if and only if BPT is one of the pool tokens
    function _getBPTIndex() internal view virtual returns (uint256) {
        return type(uint256).max;
    }

    /*///////////////////////////////////////////////////////////////
                   PREVIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view virtual override returns (uint256 amountSharesOut) {
        if (tokenIn == balLp) {
            amountSharesOut = amountTokenToDeposit;
        } else {
            IVault.JoinPoolRequest memory request = _assembleJoinRequest(tokenIn, amountTokenToDeposit);
            amountSharesOut = previewHelper.joinPoolPreview(
                balPoolId,
                address(this),
                address(this),
                request,
                _getImmutablePoolData()
            );
        }
    }

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view virtual override returns (uint256 amountTokenOut) {
        if (tokenOut == balLp) {
            amountTokenOut = amountSharesToRedeem;
        } else {
            IVault.ExitPoolRequest memory request = _assembleExitRequest(tokenOut, amountSharesToRedeem);

            amountTokenOut = previewHelper.exitPoolPreview(
                balPoolId,
                address(this),
                address(this),
                request,
                _getImmutablePoolData()
            );
        }
    }

    function _getImmutablePoolData() internal view virtual returns (bytes memory);

    /*///////////////////////////////////////////////////////////////
                               REWARDS-RELATED
    //////////////////////////////////////////////////////////////*/

    /// @notice allows owner to add new reward tokens in in case Aura does so with their pools
    function addRewardTokens(address token) external virtual onlyOwner {
        if (token == BAL_TOKEN || token == AURA_TOKEN || extraRewards.contains(token))
            revert Errors.SYInvalidRewardToken(token);

        uint256 nRewardsAura = IRewards(auraRewardManager).extraRewardsLength();
        for (uint256 i = 0; i < nRewardsAura; i++) {
            if (token == IRewards(IRewards(auraRewardManager).extraRewards(i)).rewardToken()) {
                extraRewards.push(token);
                return;
            }
        }

        revert Errors.SYInvalidRewardToken(token);
    }

    function extraRewardsLength() external view virtual returns (uint256) {
        return extraRewards.length;
    }

    function _getRewardTokens() internal view virtual override returns (address[] memory res) {
        uint256 extraRewardsLen = extraRewards.length;
        res = new address[](2 + extraRewardsLen);
        res[0] = BAL_TOKEN;
        res[1] = AURA_TOKEN;
        for (uint256 i = 0; i < extraRewardsLen; i++) {
            res[2 + i] = extraRewards[i];
        }
    }

    /// @dev if there is no extra rewards, we can call getReward with the 2nd arg (_claimExtra) to be false
    /// which helps save even more gas
    function _redeemExternalReward() internal virtual override {
        uint256 extraRewardsLen = extraRewards.length;
        if (extraRewardsLen == 0) IRewards(auraRewardManager).getReward(address(this), false);
        else IRewards(auraRewardManager).getReward(address(this), true);
    }

    /*///////////////////////////////////////////////////////////////
                    MISC FUNCTIONS FOR METADATA
    //////////////////////////////////////////////////////////////*/

    function getTokensIn() public view virtual override returns (address[] memory res);

    function getTokensOut() public view virtual override returns (address[] memory res);

    function isValidTokenIn(address token) public view virtual override returns (bool);

    function isValidTokenOut(address token) public view virtual override returns (bool);

    function assetInfo() external view returns (AssetType assetType, address assetAddress, uint8 assetDecimals) {
        return (AssetType.LIQUIDITY, balLp, IERC20Metadata(balLp).decimals());
    }
}
