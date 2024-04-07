// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../FixedPoint.sol";

// almost copy-paste from https://etherscan.io/token/0x1e19cf2d73a72ef1332c882f20534b6519be0276#code
library ComposableStableMath {
    using FixedPoint for uint256;

    uint256 internal constant _MIN_AMP = 1;
    uint256 internal constant _MAX_AMP = 5000;
    uint256 internal constant _AMP_PRECISION = 1e3;

    function _calculateInvariant(
        uint256 amplificationParameter,
        uint256[] memory balances
    ) internal pure returns (uint256) {
        unchecked {
            /**********************************************************************************************
        // invariant                                                                                 //
        // D = invariant                                                  D^(n+1)                    //
        // A = amplification coefficient      A  n^n S + D = A D n^n + -----------                   //
        // S = sum of balances                                             n^n P                     //
        // P = product of balances                                                                   //
        // n = number of tokens                                                                      //
        **********************************************************************************************/

            // Always round down, to match Vyper's arithmetic (which always truncates).

            uint256 sum = 0; // S in the Curve version
            uint256 numTokens = balances.length;
            for (uint256 i = 0; i < numTokens; i++) {
                sum = sum.add(balances[i]);
            }
            if (sum == 0) {
                return 0;
            }

            uint256 prevInvariant; // Dprev in the Curve version
            uint256 invariant = sum; // D in the Curve version
            uint256 ampTimesTotal = amplificationParameter * numTokens; // Ann in the Curve version

            for (uint256 i = 0; i < 255; i++) {
                uint256 D_P = invariant;

                for (uint256 j = 0; j < numTokens; j++) {
                    // (D_P * invariant) / (balances[j] * numTokens)
                    D_P = divDown(mul(D_P, invariant), mul(balances[j], numTokens));
                }

                prevInvariant = invariant;

                invariant = divDown(
                    mul(
                        // (ampTimesTotal * sum) / AMP_PRECISION + D_P * numTokens
                        (divDown(mul(ampTimesTotal, sum), _AMP_PRECISION).add(mul(D_P, numTokens))),
                        invariant
                    ),
                    // ((ampTimesTotal - _AMP_PRECISION) * invariant) / _AMP_PRECISION + (numTokens + 1) * D_P
                    (
                        divDown(mul((ampTimesTotal - _AMP_PRECISION), invariant), _AMP_PRECISION).add(
                            mul((numTokens + 1), D_P)
                        )
                    )
                );

                if (invariant > prevInvariant) {
                    if (invariant - prevInvariant <= 1) {
                        return invariant;
                    }
                } else if (prevInvariant - invariant <= 1) {
                    return invariant;
                }
            }

            revert("Stable Invariant did not converge");
        }
    }

    function _calcBptOutGivenExactTokensIn(
        uint256 amp,
        uint256[] memory balances,
        uint256[] memory amountsIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) internal pure returns (uint256) {
        unchecked {
            // BPT out, so we round down overall.

            // First loop calculates the sum of all token balances, which will be used to calculate
            // the current weights of each token, relative to this sum
            uint256 sumBalances = 0;
            for (uint256 i = 0; i < balances.length; i++) {
                sumBalances = sumBalances.add(balances[i]);
            }

            // Calculate the weighted balance ratio without considering fees
            uint256[] memory balanceRatiosWithFee = new uint256[](amountsIn.length);
            // The weighted sum of token balance ratios with fee
            uint256 invariantRatioWithFees = 0;
            for (uint256 i = 0; i < balances.length; i++) {
                uint256 currentWeight = balances[i].divDown(sumBalances);
                balanceRatiosWithFee[i] = balances[i].add(amountsIn[i]).divDown(balances[i]);
                invariantRatioWithFees = invariantRatioWithFees.add(balanceRatiosWithFee[i].mulDown(currentWeight));
            }

            // Second loop calculates new amounts in, taking into account the fee on the percentage excess
            uint256[] memory newBalances = new uint256[](balances.length);
            for (uint256 i = 0; i < balances.length; i++) {
                uint256 amountInWithoutFee;

                // Check if the balance ratio is greater than the ideal ratio to charge fees or not
                if (balanceRatiosWithFee[i] > invariantRatioWithFees) {
                    uint256 nonTaxableAmount = balances[i].mulDown(invariantRatioWithFees.sub(FixedPoint.ONE));
                    uint256 taxableAmount = amountsIn[i].sub(nonTaxableAmount);
                    // No need to use checked arithmetic for the swap fee, it is guaranteed to be lower than 50%
                    amountInWithoutFee = nonTaxableAmount.add(
                        taxableAmount.mulDown(FixedPoint.ONE - swapFeePercentage)
                    );
                } else {
                    amountInWithoutFee = amountsIn[i];
                }

                newBalances[i] = balances[i].add(amountInWithoutFee);
            }

            uint256 newInvariant = _calculateInvariant(amp, newBalances);
            uint256 invariantRatio = newInvariant.divDown(currentInvariant);

            // If the invariant didn't increase for any reason, we simply don't mint BPT
            if (invariantRatio > FixedPoint.ONE) {
                return bptTotalSupply.mulDown(invariantRatio - FixedPoint.ONE);
            } else {
                return 0;
            }
        }
    }

    function _calcTokenOutGivenExactBptIn(
        uint256 amp,
        uint256[] memory balances,
        uint256 tokenIndex,
        uint256 bptAmountIn,
        uint256 bptTotalSupply,
        uint256 currentInvariant,
        uint256 swapFeePercentage
    ) internal pure returns (uint256) {
        unchecked {
            // Token out, so we round down overall.

            uint256 newInvariant = bptTotalSupply.sub(bptAmountIn).divUp(bptTotalSupply).mulUp(currentInvariant);

            // Calculate amount out without fee
            uint256 newBalanceTokenIndex = _getTokenBalanceGivenInvariantAndAllOtherBalances(
                amp,
                balances,
                newInvariant,
                tokenIndex
            );
            uint256 amountOutWithoutFee = balances[tokenIndex].sub(newBalanceTokenIndex);

            // First calculate the sum of all token balances, which will be used to calculate
            // the current weight of each token
            uint256 sumBalances = 0;
            for (uint256 i = 0; i < balances.length; i++) {
                sumBalances = sumBalances.add(balances[i]);
            }

            // We can now compute how much excess balance is being withdrawn as a result of the virtual swaps, which result
            // in swap fees.
            uint256 currentWeight = balances[tokenIndex].divDown(sumBalances);
            uint256 taxablePercentage = currentWeight.complement();

            // Swap fees are typically charged on 'token in', but there is no 'token in' here, so we apply it
            // to 'token out'. This results in slightly larger price impact. Fees are rounded up.
            uint256 taxableAmount = amountOutWithoutFee.mulUp(taxablePercentage);
            uint256 nonTaxableAmount = amountOutWithoutFee.sub(taxableAmount);

            // No need to use checked arithmetic for the swap fee, it is guaranteed to be lower than 50%
            return nonTaxableAmount.add(taxableAmount.mulDown(FixedPoint.ONE - swapFeePercentage));
        }
    }

    // This function calculates the balance of a given token (tokenIndex)
    // given all the other balances and the invariant
    function _getTokenBalanceGivenInvariantAndAllOtherBalances(
        uint256 amplificationParameter,
        uint256[] memory balances,
        uint256 invariant,
        uint256 tokenIndex
    ) internal pure returns (uint256) {
        unchecked {
            // Rounds result up overall

            uint256 ampTimesTotal = amplificationParameter * balances.length;
            uint256 sum = balances[0];
            uint256 P_D = balances[0] * balances.length;
            for (uint256 j = 1; j < balances.length; j++) {
                P_D = divDown(mul(mul(P_D, balances[j]), balances.length), invariant);
                sum = sum.add(balances[j]);
            }
            // No need to use safe math, based on the loop above `sum` is greater than or equal to `balances[tokenIndex]`
            sum = sum - balances[tokenIndex];

            uint256 inv2 = mul(invariant, invariant);
            // We remove the balance from c by multiplying it
            uint256 c = mul(mul(divUp(inv2, mul(ampTimesTotal, P_D)), _AMP_PRECISION), balances[tokenIndex]);
            uint256 b = sum.add(mul(divDown(invariant, ampTimesTotal), _AMP_PRECISION));

            // We iterate to find the balance
            uint256 prevTokenBalance = 0;
            // We multiply the first iteration outside the loop with the invariant to set the value of the
            // initial approximation.
            uint256 tokenBalance = divUp(inv2.add(c), invariant.add(b));

            for (uint256 i = 0; i < 255; i++) {
                prevTokenBalance = tokenBalance;

                tokenBalance = divUp(
                    mul(tokenBalance, tokenBalance).add(c),
                    mul(tokenBalance, 2).add(b).sub(invariant)
                );

                if (tokenBalance > prevTokenBalance) {
                    if (tokenBalance - prevTokenBalance <= 1) {
                        return tokenBalance;
                    }
                } else if (prevTokenBalance - tokenBalance <= 1) {
                    return tokenBalance;
                }
            }

            revert("Stable get balance did not converge");
        }
    }

    /*///////////////////////////////////////////////////////////////
                    LEGACY MATH FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            uint256 c = a * b;
            require(a == 0 || c / a == b);
            return c;
        }
    }

    function div(uint256 a, uint256 b, bool roundUp) private pure returns (uint256) {
        return roundUp ? divUp(a, b) : divDown(a, b);
    }

    function divDown(uint256 a, uint256 b) private pure returns (uint256) {
        unchecked {
            require(b != 0);
            return a / b;
        }
    }

    function divUp(uint256 a, uint256 b) private pure returns (uint256) {
        unchecked {
            require(b != 0);

            if (a == 0) {
                return 0;
            } else {
                return 1 + (a - 1) / b;
            }
        }
    }
}
