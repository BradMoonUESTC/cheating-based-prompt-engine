// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../../../../../interfaces/Balancer/IVault.sol";
import "../../../../../../interfaces/Balancer/IERC4626LinearPool.sol";
import "../../../../../libraries/BoringOwnableUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "./LinearMath.sol";

contract LinearPreview is BoringOwnableUpgradeable, UUPSUpgradeable {
    using FixedPoint for uint256;

    struct ImmutableData {
        address pool;
        uint256 _BPT_INDEX;
        IERC20 _mainToken;
        uint256 _mainIndex;
        IERC20 _wrappedToken;
        uint256 _wrappedIndex;
    }

    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    bytes internal constant EMPTY_BYTES = abi.encode();

    constructor() initializer {}

    function initialize() external initializer {
        __BoringOwnable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function joinExitPoolPreview(
        bytes32 poolId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        IVault.SwapRequest memory request = IVault.SwapRequest({
            kind: IVault.SwapKind.GIVEN_IN,
            tokenIn: IERC20(tokenIn),
            tokenOut: IERC20(tokenOut),
            amount: amountIn,
            // unused data
            poolId: bytes32(0),
            lastChangeBlock: 0,
            from: address(0),
            to: address(0),
            userData: EMPTY_BYTES
        });

        (IERC20[] memory tokens, uint256[] memory balances, ) = IVault(BALANCER_VAULT).getPoolTokens(poolId);
        address pool = address(uint160(uint256(poolId) >> (12 * 8)));
        IERC20 mainToken = IERC20(IERC4626LinearPool(pool).getMainToken());

        uint256 indexIn;
        uint256 indexOut;
        ImmutableData memory imd;

        for (uint256 i = 0; i < tokens.length; ) {
            if (tokens[i] == mainToken) {
                imd._mainToken = mainToken;
                imd._mainIndex = i;
            } else if (tokens[i] == IERC20(pool)) {
                imd.pool = pool;
                imd._BPT_INDEX = i;
            } else {
                imd._wrappedToken = tokens[i];
                imd._wrappedIndex = i;
            }

            if (tokens[i] == IERC20(tokenIn)) {
                indexIn = i;
            } else if (tokens[i] == IERC20(tokenOut)) {
                indexOut = i;
            }
            unchecked {
                i++;
            }
        }

        return _onSwapGeneral(request, balances, indexIn, indexOut, imd);
    }

    function _onSwapGeneral(
        IVault.SwapRequest memory request,
        uint256[] memory balances,
        uint256 indexIn,
        uint256 indexOut,
        ImmutableData memory imd
    ) internal view returns (uint256) {
        // Upscale balances by the scaling factors (taking into account the wrapped token rate)
        uint256[] memory scalingFactors = IERC4626LinearPool(imd.pool).getScalingFactors();
        _upscaleArray(balances, scalingFactors);

        (uint256 lowerTarget, uint256 upperTarget) = IERC4626LinearPool(imd.pool).getTargets();
        LinearMath.Params memory params = LinearMath.Params({
            fee: IERC4626LinearPool(imd.pool).getSwapFeePercentage(),
            lowerTarget: lowerTarget,
            upperTarget: upperTarget
        });

        assert(request.kind == IVault.SwapKind.GIVEN_IN);
        // The amount given is for token in, the amount calculated is for token out
        request.amount = _upscale(request.amount, scalingFactors[indexIn]);
        uint256 amountOut = _onSwapGivenIn(request, balances, params, imd);

        // amountOut tokens are exiting the Pool, so we round down.
        return _downscaleDown(amountOut, scalingFactors[indexOut]);
    }

    function _onSwapGivenIn(
        IVault.SwapRequest memory request,
        uint256[] memory balances,
        LinearMath.Params memory params,
        ImmutableData memory imd
    ) internal view returns (uint256) {
        if (request.tokenIn == IERC20(imd.pool)) {
            return _swapGivenBptIn(request, balances, params, imd);
        } else if (request.tokenIn == imd._mainToken) {
            return _swapGivenMainIn(request, balances, params, imd);
        } else if (request.tokenIn == imd._wrappedToken) {
            return _swapGivenWrappedIn(request, balances, params, imd);
        } else {
            assert(false);
        }
    }

    function _swapGivenBptIn(
        IVault.SwapRequest memory request,
        uint256[] memory balances,
        LinearMath.Params memory params,
        ImmutableData memory imd
    ) internal view returns (uint256) {
        // _require(
        //     request.tokenOut == _mainToken || request.tokenOut == _wrappedToken,
        //     Errors.INVALID_TOKEN
        // );
        return
            (request.tokenOut == imd._mainToken ? LinearMath._calcMainOutPerBptIn : LinearMath._calcWrappedOutPerBptIn)(
                request.amount,
                balances[imd._mainIndex],
                balances[imd._wrappedIndex],
                _getVirtualSupply(balances[imd._BPT_INDEX], imd.pool),
                params
            );
    }

    function _swapGivenMainIn(
        IVault.SwapRequest memory request,
        uint256[] memory balances,
        LinearMath.Params memory params,
        ImmutableData memory imd
    ) internal view returns (uint256) {
        // _require(
        //     request.tokenOut == _wrappedToken || request.tokenOut == this,
        //     Errors.INVALID_TOKEN
        // );
        return
            request.tokenOut == IERC20(imd.pool)
                ? LinearMath._calcBptOutPerMainIn(
                    request.amount,
                    balances[imd._mainIndex],
                    balances[imd._wrappedIndex],
                    _getVirtualSupply(balances[imd._BPT_INDEX], imd.pool),
                    params
                )
                : LinearMath._calcWrappedOutPerMainIn(request.amount, balances[imd._mainIndex], params);
    }

    function _swapGivenWrappedIn(
        IVault.SwapRequest memory request,
        uint256[] memory balances,
        LinearMath.Params memory params,
        ImmutableData memory imd
    ) internal view returns (uint256) {
        // _require(request.tokenOut == _mainToken || request.tokenOut == this, Errors.INVALID_TOKEN);
        return
            request.tokenOut == IERC20(imd.pool)
                ? LinearMath._calcBptOutPerWrappedIn(
                    request.amount,
                    balances[imd._mainIndex],
                    balances[imd._wrappedIndex],
                    _getVirtualSupply(balances[imd._BPT_INDEX], imd.pool),
                    params
                )
                : LinearMath._calcMainOutPerWrappedIn(request.amount, balances[imd._mainIndex], params);
    }

    function _getVirtualSupply(uint256 bptBalance, address pool) internal view returns (uint256) {
        return (IERC20(pool).totalSupply()).sub(bptBalance);
    }

    function _upscale(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.mulDown(amount, scalingFactor);
    }

    function _downscaleDown(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return FixedPoint.divDown(amount, scalingFactor);
    }

    function _upscaleArray(uint256[] memory amounts, uint256[] memory scalingFactors) internal pure {
        uint256 length = amounts.length;
        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = FixedPoint.mulDown(amounts[i], scalingFactors[i]);
        }
    }
}
