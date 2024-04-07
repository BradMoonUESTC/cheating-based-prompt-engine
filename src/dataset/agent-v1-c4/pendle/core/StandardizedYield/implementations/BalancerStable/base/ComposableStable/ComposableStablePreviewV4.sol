// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../../../../interfaces/Balancer/IComposableStable.sol";

import "../FixedPoint.sol";
import "../StablePoolUserData.sol";

import "./ComposableStableMath.sol";
import "./ComposableStablePreview.sol";

contract ComposableStablePreviewV4 is ComposableStablePreview {
    using ComposableStableMath for uint256;
    using StablePoolUserData for bytes;
    using FixedPoint for uint256;

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

        TokenRateCache[] memory caches = _beforeSwapJoinExit(imd);

        uint256[] memory scalingFactors = _scalingFactors(imd, caches);

        // skip totalSupply == 0 case

        _upscaleArray(balances, scalingFactors);
        (bptAmountOut, ) = _onJoinPool(
            poolId,
            sender,
            recipient,
            balances,
            lastChangeBlock,
            protocolSwapFeePercentage,
            scalingFactors,
            userData,
            imd,
            caches
        );

        // skip _mintPoolTokens, _downscaleUpArray

        // we return bptAmountOut instead of minting
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
    ) internal view override returns (uint256 amountTokenOut) {
        ImmutableData memory imd = abi.decode(poolImmutableData, (ImmutableData));

        uint256 bptAmountIn;
        uint256[] memory amountsOut;

        // skip recovery mode

        TokenRateCache[] memory caches = _beforeSwapJoinExit(imd);

        uint256[] memory scalingFactors = _scalingFactors(imd, caches);
        _upscaleArray(balances, scalingFactors);

        (bptAmountIn, amountsOut) = _onExitPool(
            poolId,
            sender,
            recipient,
            balances,
            lastChangeBlock,
            protocolSwapFeePercentage, // assume no recovery mode
            scalingFactors,
            userData,
            imd,
            caches
        );

        _downscaleDownArray(amountsOut, scalingFactors);

        // skip burnPoolTokens

        for (uint256 i = 0; i < amountsOut.length; i++) {
            if (amountsOut[i] > 0) return amountsOut[i];
        }
    }

    function _onJoinPool(
        bytes32,
        address,
        address,
        uint256[] memory registeredBalances,
        uint256,
        uint256,
        uint256[] memory scalingFactors,
        bytes memory userData,
        ImmutableData memory imd,
        TokenRateCache[] memory caches
    ) internal view returns (uint256, uint256[] memory) {
        return _onJoinExitPool(true, registeredBalances, scalingFactors, userData, imd, caches);
    }

    function _onExitPool(
        bytes32,
        address,
        address,
        uint256[] memory registeredBalances,
        uint256,
        uint256,
        uint256[] memory scalingFactors,
        bytes memory userData,
        ImmutableData memory imd,
        TokenRateCache[] memory caches
    ) internal view returns (uint256, uint256[] memory) {
        return _onJoinExitPool(false, registeredBalances, scalingFactors, userData, imd, caches);
    }

    /**
     * @return bptAmount
     * @return amountsDelta this will not contain bpt item since it will be discarded on the upper level
     */
    function _onJoinExitPool(
        bool isJoin,
        uint256[] memory registeredBalances,
        uint256[] memory scalingFactors,
        bytes memory userData,
        ImmutableData memory imd,
        TokenRateCache[] memory caches
    ) internal view returns (uint256 bptAmount, uint256[] memory amountsDelta) {
        (
            uint256 preJoinExitSupply,
            uint256[] memory balances,
            uint256 currentAmp,
            uint256 preJoinExitInvariant
        ) = _beforeJoinExit(registeredBalances, imd, caches);

        function(uint256[] memory, uint256, uint256, uint256, uint256[] memory, bytes memory, ImmutableData memory)
            internal
            view
            returns (uint256, uint256[] memory) _doJoinOrExit = (isJoin ? _doJoin : _doExit);

        (bptAmount, amountsDelta) = _doJoinOrExit(
            balances,
            currentAmp,
            preJoinExitSupply,
            preJoinExitInvariant,
            scalingFactors,
            userData,
            imd
        );
        amountsDelta = _addBptItem(amountsDelta, 0, imd);

        // _mutateAmounts

        // skip _updateInvariantAfterJoinExit here
    }

    function _addBptItem(
        uint256[] memory amounts,
        uint256 bptAmount,
        ImmutableData memory imd
    ) internal pure returns (uint256[] memory registeredTokenAmounts) {
        registeredTokenAmounts = new uint256[](amounts.length + 1);
        for (uint256 i = 0; i < registeredTokenAmounts.length; i++) {
            registeredTokenAmounts[i] = i == imd.bptIndex ? bptAmount : amounts[i < imd.bptIndex ? i : i - 1];
        }
    }

    function _doJoin(
        uint256[] memory balances,
        uint256 currentAmp,
        uint256 preJoinExitSupply,
        uint256 preJoinExitInvariant,
        uint256[] memory scalingFactors,
        bytes memory userData,
        ImmutableData memory imd
    ) internal view returns (uint256, uint256[] memory) {
        // this is always true given Pendle SY context
        return
            _joinExactTokensInForBPTOut(
                preJoinExitSupply,
                preJoinExitInvariant,
                currentAmp,
                balances,
                scalingFactors,
                userData,
                imd
            );
    }

    function _joinExactTokensInForBPTOut(
        uint256 actualSupply,
        uint256 preJoinExitInvariant,
        uint256 currentAmp,
        uint256[] memory balances,
        uint256[] memory scalingFactors,
        bytes memory userData,
        ImmutableData memory imd
    ) private view returns (uint256, uint256[] memory) {
        (uint256[] memory amountsIn, ) = userData.exactTokensInForBptOut();

        // The user-provided amountsIn is unscaled, so we address that.
        _upscaleArray(amountsIn, _dropBptItem(imd, scalingFactors));

        uint256 bptAmountOut = currentAmp._calcBptOutGivenExactTokensIn(
            balances,
            amountsIn,
            actualSupply,
            preJoinExitInvariant,
            IBasePool(imd.LP).getSwapFeePercentage()
        );
        return (bptAmountOut, amountsIn);
    }

    function _doExit(
        uint256[] memory balances,
        uint256 currentAmp,
        uint256 preJoinExitSupply,
        uint256 preJoinExitInvariant,
        uint256[] memory /*scalingFactors*/,
        bytes memory userData,
        ImmutableData memory imd
    ) internal view returns (uint256, uint256[] memory) {
        // this is always true given Pendle SY context
        return _exitExactBPTInForTokenOut(preJoinExitSupply, preJoinExitInvariant, currentAmp, balances, userData, imd);
    }

    function _exitExactBPTInForTokenOut(
        uint256 actualSupply,
        uint256 preJoinExitInvariant,
        uint256 currentAmp,
        uint256[] memory balances,
        bytes memory userData,
        ImmutableData memory imd
    ) private view returns (uint256, uint256[] memory) {
        (uint256 bptAmountIn, uint256 tokenIndex) = userData.exactBptInForTokenOut();

        uint256[] memory amountsOut = new uint256[](balances.length);

        amountsOut[tokenIndex] = currentAmp._calcTokenOutGivenExactBptIn(
            balances,
            tokenIndex,
            bptAmountIn,
            actualSupply,
            preJoinExitInvariant,
            IBasePool(imd.LP).getSwapFeePercentage()
        );

        return (bptAmountIn, amountsOut);
    }

    function _beforeJoinExit(
        uint256[] memory registeredBalances,
        ImmutableData memory imd,
        TokenRateCache[] memory caches
    ) internal view returns (uint256, uint256[] memory, uint256, uint256) {
        (uint256 lastJoinExitAmp, uint256 lastPostJoinExitInvariant) = IComposableStable(imd.LP).getLastJoinExitData();

        (
            uint256 preJoinExitSupply,
            uint256[] memory balances,
            uint256 oldAmpPreJoinExitInvariant
        ) = _payProtocolFeesBeforeJoinExit(registeredBalances, lastJoinExitAmp, lastPostJoinExitInvariant, imd, caches);

        (uint256 currentAmp, , ) = IComposableStable(imd.LP).getAmplificationParameter();
        uint256 preJoinExitInvariant = currentAmp == lastJoinExitAmp
            ? oldAmpPreJoinExitInvariant
            : currentAmp._calculateInvariant(balances);

        return (preJoinExitSupply, balances, currentAmp, preJoinExitInvariant);
    }

    function _payProtocolFeesBeforeJoinExit(
        uint256[] memory registeredBalances,
        uint256 lastJoinExitAmp,
        uint256 lastPostJoinExitInvariant,
        ImmutableData memory imd,
        TokenRateCache[] memory caches
    ) internal view returns (uint256, uint256[] memory, uint256) {
        (uint256 virtualSupply, uint256[] memory balances) = _dropBptItemFromBalances(imd, registeredBalances);

        (
            uint256 expectedProtocolOwnershipPercentage,
            uint256 currentInvariantWithLastJoinExitAmp
        ) = _getProtocolPoolOwnershipPercentage(balances, lastJoinExitAmp, lastPostJoinExitInvariant, imd, caches);

        uint256 protocolFeeAmount = _calculateAdjustedProtocolFeeAmount(
            virtualSupply,
            expectedProtocolOwnershipPercentage
        );

        // skip _payProtocolFee, which will make the LP balance from this point onwards to be off

        return (virtualSupply + protocolFeeAmount, balances, currentInvariantWithLastJoinExitAmp);
    }

    function _getProtocolPoolOwnershipPercentage(
        uint256[] memory balances,
        uint256 lastJoinExitAmp,
        uint256 lastPostJoinExitInvariant,
        ImmutableData memory imd,
        TokenRateCache[] memory caches
    ) internal view returns (uint256, uint256) {
        (
            uint256 swapFeeGrowthInvariant,
            uint256 totalNonExemptGrowthInvariant,
            uint256 totalGrowthInvariant
        ) = _getGrowthInvariants(balances, lastJoinExitAmp, imd, caches);

        uint256 swapFeeGrowthInvariantDelta = (swapFeeGrowthInvariant > lastPostJoinExitInvariant)
            ? swapFeeGrowthInvariant - lastPostJoinExitInvariant
            : 0;
        uint256 nonExemptYieldGrowthInvariantDelta = (totalNonExemptGrowthInvariant > swapFeeGrowthInvariant)
            ? totalNonExemptGrowthInvariant - swapFeeGrowthInvariant
            : 0;

        uint256 protocolSwapFeePercentage = swapFeeGrowthInvariantDelta.divDown(totalGrowthInvariant).mulDown(
            IComposableStable(imd.LP).getProtocolFeePercentageCache(0) // ProtocolFeeType.SWAP // can't get better
        );

        uint256 protocolYieldPercentage = nonExemptYieldGrowthInvariantDelta.divDown(totalGrowthInvariant).mulDown(
            IComposableStable(imd.LP).getProtocolFeePercentageCache(2) // ProtocolFeeType.YIELD // can't get better
        );

        // These percentages can then be simply added to compute the total protocol Pool ownership percentage.
        // This is naturally bounded above by FixedPoint.ONE so this addition cannot overflow.
        return (protocolSwapFeePercentage + protocolYieldPercentage, totalGrowthInvariant);
    }

    function _getGrowthInvariants(
        uint256[] memory balances,
        uint256 lastJoinExitAmp,
        ImmutableData memory imd,
        TokenRateCache[] memory caches
    )
        internal
        pure
        returns (uint256 swapFeeGrowthInvariant, uint256 totalNonExemptGrowthInvariant, uint256 totalGrowthInvariant)
    {
        swapFeeGrowthInvariant = lastJoinExitAmp._calculateInvariant(_getAdjustedBalances(balances, true, imd, caches));

        if (imd.noTokensExempt) {
            totalNonExemptGrowthInvariant = lastJoinExitAmp._calculateInvariant(balances);
            totalGrowthInvariant = totalNonExemptGrowthInvariant;
        } else if (imd.allTokensExempt) {
            totalNonExemptGrowthInvariant = swapFeeGrowthInvariant;
            totalGrowthInvariant = lastJoinExitAmp._calculateInvariant(balances);
        } else {
            totalNonExemptGrowthInvariant = lastJoinExitAmp._calculateInvariant(
                _getAdjustedBalances(balances, false, imd, caches)
            );

            totalGrowthInvariant = lastJoinExitAmp._calculateInvariant(balances);
        }
    }

    function _getAdjustedBalances(
        uint256[] memory balances,
        bool ignoreExemptFlags,
        ImmutableData memory imd,
        TokenRateCache[] memory tokenRateCaches
    ) internal pure returns (uint256[] memory) {
        uint256 totalTokensWithoutBpt = balances.length;
        uint256[] memory adjustedBalances = new uint256[](totalTokensWithoutBpt);

        for (uint256 i = 0; i < totalTokensWithoutBpt; ++i) {
            uint256 skipBptIndex = i >= imd.bptIndex ? i + 1 : i;
            adjustedBalances[i] = _isTokenExemptFromYieldProtocolFee(imd, skipBptIndex) ||
                (ignoreExemptFlags && _hasRateProvider(imd, skipBptIndex))
                ? _adjustedBalance(balances[i], tokenRateCaches[skipBptIndex])
                : balances[i];
        }

        return adjustedBalances;
    }

    function _adjustedBalance(uint256 balance, TokenRateCache memory cache) private pure returns (uint256) {
        return (balance * cache.oldRate) / cache.currentRate;
    }

    function _calculateAdjustedProtocolFeeAmount(
        uint256 supply,
        uint256 basePercentage
    ) internal pure returns (uint256) {
        return supply.mulDown(basePercentage).divDown(basePercentage.complement());
    }

    function _dropBptItemFromBalances(
        ImmutableData memory imd,
        uint256[] memory registeredBalances
    ) internal view returns (uint256, uint256[] memory) {
        return (_getVirtualSupply(imd, registeredBalances[imd.bptIndex]), _dropBptItem(imd, registeredBalances));
    }

    function _dropBptItem(ImmutableData memory imd, uint256[] memory amounts) internal pure returns (uint256[] memory) {
        uint256[] memory amountsWithoutBpt = new uint256[](amounts.length - 1);
        for (uint256 i = 0; i < amountsWithoutBpt.length; i++) {
            amountsWithoutBpt[i] = amounts[i < imd.bptIndex ? i : i + 1];
        }

        return amountsWithoutBpt;
    }

    function _getVirtualSupply(ImmutableData memory imd, uint256 bptBalance) internal view returns (uint256) {
        return (IERC20(imd.LP).totalSupply()).sub(bptBalance); // can't get better
    }

    function _beforeSwapJoinExit(
        ImmutableData memory imd
    ) internal view returns (TokenRateCache[] memory tokenRateCaches) {
        return _cacheTokenRatesIfNecessary(imd);
    }

    function _cacheTokenRatesIfNecessary(
        ImmutableData memory imd
    ) internal view returns (TokenRateCache[] memory tokenRateCaches) {
        tokenRateCaches = new TokenRateCache[](imd.totalTokens);

        for (uint256 i = 0; i < imd.totalTokens; ++i) {
            tokenRateCaches[i] = _cacheTokenRateIfNecessary(i, imd);
        }
    }

    /**
     * @dev Caches the rate for a token if necessary. It ignores the call if there is no provider set.
     */
    function _cacheTokenRateIfNecessary(
        uint256 index,
        ImmutableData memory imd
    ) internal view returns (TokenRateCache memory res) {
        if (index == imd.bptIndex || !_hasRateProvider(imd, index)) return res;

        uint256 expires;
        (res.currentRate, res.oldRate, , expires) = IComposableStable(imd.LP).getTokenRateCache(
            IERC20(imd.poolTokens[index])
        );

        if (block.timestamp > expires) {
            res.currentRate = IRateProvider(imd.rateProviders[index]).getRate();
        }
    }

    function _scalingFactors(
        ImmutableData memory imd,
        TokenRateCache[] memory caches
    ) internal view virtual returns (uint256[] memory) {
        // There is no need to check the arrays length since both are based on `_getTotalTokens`
        uint256[] memory scalingFactors = new uint256[](imd.totalTokens);

        for (uint256 i = 0; i < imd.totalTokens; ++i) {
            scalingFactors[i] = imd.rawScalingFactors[i].mulDown(_getTokenRate(caches, i));
        }

        return scalingFactors;
    }

    function _getTokenRate(TokenRateCache[] memory caches, uint256 index) internal view virtual returns (uint256) {
        return caches[index].currentRate == 0 ? FixedPoint.ONE : caches[index].currentRate;
    }

    /*///////////////////////////////////////////////////////////////
                               Helpers functions
    //////////////////////////////////////////////////////////////*/

    function _upscaleArray(uint256[] memory amounts, uint256[] memory scalingFactors) internal pure {
        uint256 length = amounts.length;
        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = FixedPoint.mulDown(amounts[i], scalingFactors[i]);
        }
    }

    function _downscaleDownArray(uint256[] memory amounts, uint256[] memory scalingFactors) internal pure {
        uint256 length = amounts.length;
        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = FixedPoint.divDown(amounts[i], scalingFactors[i]);
        }
    }

    function _hasRateProvider(ImmutableData memory imd, uint256 index) internal pure returns (bool) {
        return address(imd.rateProviders[index]) != address(0);
    }

    function _isTokenExemptFromYieldProtocolFee(ImmutableData memory imd, uint256 index) internal pure returns (bool) {
        return imd.isExemptFromYieldProtocolFee[index];
    }
}
