// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import "../../../../../../interfaces/Balancer/IMetaStablePool.sol";
import "../../../../../../interfaces/Balancer/IRateProvider.sol";

import "../FixedPoint.sol";
import "./MetaStableMath.sol";
import "../StablePoolUserData.sol";

import "../StablePreviewBase.sol";
import "../../../../../libraries/BoringOwnableUpgradeable.sol";

// this contract will be upgradable for the first 3-6 months, then its upgradeability will be relinquished
contract MetaStablePreview is StablePreviewBase, BoringOwnableUpgradeable, UUPSUpgradeable {
    using FixedPoint for uint256;
    using MetaStableMath for uint256;
    using StablePoolUserData for bytes;

    struct ImmutableData {
        address LP;
        address[] poolTokens;
        address[] rateProviders;
        uint256[] rawScalingFactors;
    }

    constructor() initializer {}

    function initialize() external initializer {
        __BoringOwnable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function onJoinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData,
        bytes memory poolImmutableData
    ) internal view override returns (uint256 bptAmountOut) {
        ImmutableData memory imd = abi.decode(poolImmutableData, (ImmutableData));

        uint256[] memory caches = _cachePriceRatesIfNecessary(imd);

        uint256[] memory scalingFactors = _scalingFactors(imd, caches);

        // skip totalSupply == 0 case

        _upscaleArray(balances, scalingFactors);
        (bptAmountOut, , ) = _onJoinPool(
            poolId,
            sender,
            recipient,
            balances,
            lastChangeBlock,
            protocolSwapFeePercentage,
            scalingFactors,
            userData,
            imd
        );

        // skip _mintPoolTokens, _downscale
    }

    function onExitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData,
        bytes memory poolImmutableData
    ) internal view virtual override returns (uint256 amountTokenOut) {
        ImmutableData memory imd = abi.decode(poolImmutableData, (ImmutableData));

        uint256[] memory caches = _cachePriceRatesIfNecessary(imd);

        uint256[] memory scalingFactors = _scalingFactors(imd, caches);
        _upscaleArray(balances, scalingFactors);

        (, uint256[] memory amountsOut, ) = _onExitPool(
            poolId,
            sender,
            recipient,
            balances,
            lastChangeBlock,
            protocolSwapFeePercentage,
            scalingFactors,
            userData,
            imd
        );

        // skip burnPoolTokens

        _downscaleDownArray(amountsOut, scalingFactors);
        // skip _downscaleDownArray of dueProtocolFeeAmounts

        for (uint256 i = 0; i < amountsOut.length; i++) {
            if (amountsOut[i] > 0) {
                amountTokenOut = amountsOut[i];
            }
        }
    }

    function _onJoinPool(
        bytes32,
        address,
        address,
        uint256[] memory balances,
        uint256,
        uint256 protocolSwapFeePercentage,
        uint256[] memory scalingFactors,
        bytes memory userData,
        ImmutableData memory imd
    ) internal view returns (uint256, uint256[] memory, uint256[] memory) {
        // skip _updateOracle

        uint256[] memory dueProtocolFeeAmounts = _getDueProtocolFeeAmounts(balances, protocolSwapFeePercentage, imd);

        _mutateAmounts(balances, dueProtocolFeeAmounts, FixedPoint.sub);
        (uint256 bptAmountOut, uint256[] memory amountsIn) = _doJoin(balances, scalingFactors, userData, imd);

        // skip _updateInvariantAfterJoin

        return (bptAmountOut, amountsIn, dueProtocolFeeAmounts);
    }

    function _onExitPool(
        bytes32,
        address,
        address,
        uint256[] memory balances,
        uint256,
        uint256 protocolSwapFeePercentage,
        uint256[] memory scalingFactors,
        bytes memory userData,
        ImmutableData memory imd
    )
        internal
        view
        virtual
        returns (uint256 bptAmountIn, uint256[] memory amountsOut, uint256[] memory dueProtocolFeeAmounts)
    {
        // skip _updateOracle

        dueProtocolFeeAmounts = _getDueProtocolFeeAmounts(balances, protocolSwapFeePercentage, imd);

        _mutateAmounts(balances, dueProtocolFeeAmounts, FixedPoint.sub);

        (bptAmountIn, amountsOut) = _doExit(balances, scalingFactors, userData, imd);

        // skip pause case

        // skip _updateInvariantAfterExit

        return (bptAmountIn, amountsOut, dueProtocolFeeAmounts);
    }

    function _getDueProtocolFeeAmounts(
        uint256[] memory balances,
        uint256 protocolSwapFeePercentage,
        ImmutableData memory imd
    ) private view returns (uint256[] memory) {
        uint256[] memory dueProtocolFeeAmounts = new uint256[](2);

        if (protocolSwapFeePercentage == 0) {
            return dueProtocolFeeAmounts;
        }

        uint256 chosenTokenIndex = 0;
        uint256 maxBalance = balances[0];
        for (uint256 i = 1; i < 2; ++i) {
            uint256 currentBalance = balances[i];
            if (currentBalance > maxBalance) {
                chosenTokenIndex = i;
                maxBalance = currentBalance;
            }
        }

        (uint256 _lastInvariant, uint256 _lastInvariantAmp) = IMetaStablePool(imd.LP).getLastInvariant();
        dueProtocolFeeAmounts[chosenTokenIndex] = MetaStableMath._calcDueTokenProtocolSwapFeeAmount(
            _lastInvariantAmp,
            balances,
            _lastInvariant,
            chosenTokenIndex,
            protocolSwapFeePercentage
        );

        return dueProtocolFeeAmounts;
    }

    function _doJoin(
        uint256[] memory balances,
        uint256[] memory scalingFactors,
        bytes memory userData,
        ImmutableData memory imd
    ) private view returns (uint256, uint256[] memory) {
        return _joinExactTokensInForBPTOut(balances, scalingFactors, userData, imd);
    }

    function _joinExactTokensInForBPTOut(
        uint256[] memory balances,
        uint256[] memory scalingFactors,
        bytes memory userData,
        ImmutableData memory imd
    ) private view returns (uint256, uint256[] memory) {
        (uint256[] memory amountsIn, ) = userData.exactTokensInForBptOut();

        _upscaleArray(amountsIn, scalingFactors);

        (uint256 currentAmp, , ) = IMetaStablePool(imd.LP).getAmplificationParameter();
        uint256 bptAmountOut = MetaStableMath._calcBptOutGivenExactTokensIn(
            currentAmp,
            balances,
            amountsIn,
            IMetaStablePool(imd.LP).totalSupply(),
            IMetaStablePool(imd.LP).getSwapFeePercentage()
        );

        return (bptAmountOut, amountsIn);
    }

    function _doExit(
        uint256[] memory balances,
        uint256[] memory,
        bytes memory userData,
        ImmutableData memory imd
    ) private view returns (uint256, uint256[] memory) {
        return _exitExactBPTInForTokenOut(balances, userData, imd);
    }

    function _exitExactBPTInForTokenOut(
        uint256[] memory balances,
        bytes memory userData,
        ImmutableData memory imd
    ) private view returns (uint256, uint256[] memory) {
        // This exit function is disabled if the contract is paused.

        (uint256 bptAmountIn, uint256 tokenIndex) = userData.exactBptInForTokenOut();
        // Note that there is no minimum amountOut parameter: this is handled by `IVault.exitPool`.

        // We exit in a single token, so initialize amountsOut with zeros
        uint256[] memory amountsOut = new uint256[](2);

        // And then assign the result to the selected token
        (uint256 currentAmp, , ) = IMetaStablePool(imd.LP).getAmplificationParameter();
        amountsOut[tokenIndex] = MetaStableMath._calcTokenOutGivenExactBptIn(
            currentAmp,
            balances,
            tokenIndex,
            bptAmountIn,
            IMetaStablePool(imd.LP).totalSupply(),
            IMetaStablePool(imd.LP).getSwapFeePercentage()
        );

        return (bptAmountIn, amountsOut);
    }

    function _scalingFactors(
        ImmutableData memory imd,
        uint256[] memory caches
    ) internal view virtual returns (uint256[] memory) {
        uint256[] memory scalingFactors = new uint256[](2);

        for (uint256 i = 0; i < 2; ++i) {
            scalingFactors[i] = imd.rawScalingFactors[i].mulDown(_priceRate(caches, i));
        }

        return scalingFactors;
    }

    function _priceRate(uint256[] memory caches, uint256 index) internal view virtual returns (uint256) {
        return caches[index] == 0 ? FixedPoint.ONE : caches[index];
    }

    function _cachePriceRatesIfNecessary(ImmutableData memory imd) internal view returns (uint256[] memory res) {
        res = new uint256[](2);
        res[0] = _cachePriceRateIfNecessary(0, imd);
        res[1] = _cachePriceRateIfNecessary(1, imd);
    }

    function _cachePriceRateIfNecessary(uint256 index, ImmutableData memory imd) internal view returns (uint256 res) {
        if (!_hasRateProvider(imd, index)) return res;

        uint256 expires;
        (res, , expires) = IMetaStablePool(imd.LP).getPriceRateCache(IERC20(imd.poolTokens[index]));

        if (block.timestamp > expires) {
            res = IRateProvider(imd.rateProviders[index]).getRate();
        }
    }

    /*///////////////////////////////////////////////////////////////
                               Helpers functions
    //////////////////////////////////////////////////////////////*/

    function _upscaleArray(uint256[] memory amounts, uint256[] memory scalingFactors) internal pure {
        require(amounts.length == scalingFactors.length, "Array length mismatch");

        uint256 length = amounts.length;
        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = FixedPoint.mulDown(amounts[i], scalingFactors[i]);
        }
    }

    function _downscaleDownArray(uint256[] memory amounts, uint256[] memory scalingFactors) internal pure {
        require(amounts.length == scalingFactors.length, "Array length mismatch");

        uint256 length = amounts.length;
        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = FixedPoint.divDown(amounts[i], scalingFactors[i]);
        }
    }

    function _mutateAmounts(
        uint256[] memory toMutate,
        uint256[] memory arguments,
        function(uint256, uint256) pure returns (uint256) mutation
    ) private pure {
        for (uint256 i = 0; i < 2; ++i) {
            toMutate[i] = mutation(toMutate[i], arguments[i]);
        }
    }

    function _hasRateProvider(ImmutableData memory imd, uint256 index) internal pure returns (bool) {
        return address(imd.rateProviders[index]) != address(0);
    }
}
