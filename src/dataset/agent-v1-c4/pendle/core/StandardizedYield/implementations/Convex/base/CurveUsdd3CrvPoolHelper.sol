// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../../../libraries/math/PMath.sol";
import "../../../../../interfaces/Curve/ICrvPool.sol";
import "./Curve3CrvPoolHelper.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library CurveUsdd3CrvPoolHelper {
    using PMath for uint256;

    uint256 internal constant N_COINS = 2;
    uint256 internal constant A_PRECISION = 100;
    uint256 internal constant PRECISION = 10 ** 18;
    uint256 internal constant rate_multiplier = 10 ** 18;
    uint256 internal constant FEE_DENOMINATOR = 10 ** 10;

    // LP == POOL
    address internal constant POOL = 0xe6b5CC1B4b47305c58392CE3D359B10282FC36Ea;
    address internal constant USDD = 0x0C10bF8FcB7Bf5412187A595ab97a3609160b5c6;
    address internal constant LP_3CRV = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;

    function _getBalances() internal view returns (uint256[N_COINS] memory balances) {
        balances[0] = ICrvPool(POOL).balances(0);
        balances[1] = ICrvPool(POOL).balances(1);
    }

    function _getTokenAmounts(address token, uint256 amount) internal pure returns (uint256[N_COINS] memory res) {
        res[token == USDD ? 0 : 1] = amount;
    }

    // ----------------- Forked from https://etherscan.io/address/0xe6b5CC1B4b47305c58392CE3D359B10282FC36Ea#code -----------------
    function previewAddLiquidity(address token, uint256 amount) internal view returns (uint256) {
        uint256 amp = ICrvPool(POOL).A_precise();

        uint256[N_COINS] memory rates;

        rates[0] = rate_multiplier;

        if (token == USDD || token == LP_3CRV) {
            rates[1] = Curve3CrvPoolHelper.get_virtual_price();
        } else {
            (amount, rates[1]) = Curve3CrvPoolHelper.preview3CrvDeposit(token, amount);
            token = LP_3CRV;
        }

        uint256[N_COINS] memory amounts = _getTokenAmounts(token, amount);

        uint256[N_COINS] memory old_balances = _getBalances();
        uint256 D0 = get_D_mem(rates, old_balances, amp);
        uint256[N_COINS] memory new_balances = arrayClone(old_balances);

        uint256 total_supply = IERC20(POOL).totalSupply();
        for (uint256 i = 0; i < N_COINS; ++i) {
            new_balances[i] += amounts[i];
        }

        // Invariant after change
        uint256 D1 = get_D_mem(rates, new_balances, amp);
        assert(D1 > D0);

        // We need to recalculate the invariant accounting for fees
        // to calculate fair user's share
        uint256[N_COINS] memory fees;
        uint256 mint_amount = 0;

        uint256 base_fee = (ICrvPool(POOL).fee() * N_COINS) / (4 * (N_COINS - 1));
        for (uint256 i = 0; i < N_COINS; ++i) {
            uint256 ideal_balance = (D1 * old_balances[i]) / D0;
            uint256 difference = 0;
            uint256 new_balance = new_balances[i];
            if (ideal_balance > new_balance) {
                difference = ideal_balance - new_balance;
            } else {
                difference = new_balance - ideal_balance;
            }
            fees[i] = (base_fee * difference) / FEE_DENOMINATOR;
            new_balances[i] -= fees[i];
        }
        uint256 D2 = get_D_mem(rates, new_balances, amp);
        mint_amount = (total_supply * (D2 - D0)) / D0;
        return mint_amount;
    }

    function get_D_mem(
        uint256[N_COINS] memory _rates,
        uint256[N_COINS] memory _balances,
        uint256 _amp
    ) internal pure returns (uint256) {
        uint256[N_COINS] memory xp = _xp_mem(_rates, _balances);
        return get_D(xp, _amp);
    }

    function _xp_mem(
        uint256[N_COINS] memory _rates,
        uint256[N_COINS] memory balances
    ) internal pure returns (uint256[N_COINS] memory) {
        uint256[N_COINS] memory result;
        for (uint256 i = 0; i < N_COINS; ++i) {
            result[i] = (balances[i] * _rates[i]) / PRECISION;
        }
        return result;
    }

    function get_D(uint256[N_COINS] memory _xp, uint256 _amp) internal pure returns (uint256) {
        uint256 S = 0;
        uint256 Dprev = 0;
        for (uint256 k = 0; k < N_COINS; ++k) {
            S += _xp[k];
        }
        if (S == 0) return 0;

        uint256 D = S;
        uint256 Ann = _amp * N_COINS;
        for (uint256 _i = 0; _i < 255; ++_i) {
            uint256 D_P = D;
            for (uint256 k = 0; k < N_COINS; ++k) {
                D_P = (D_P * D) / (_xp[k] * N_COINS);
            }
            Dprev = D;
            D =
                (((Ann * S) / A_PRECISION + D_P * N_COINS) * D) /
                (((Ann - A_PRECISION) * D) / A_PRECISION + (N_COINS + 1) * D_P);

            if (D > Dprev) {
                if (D - Dprev <= 1) {
                    return D;
                }
            } else {
                if (Dprev - D <= 1) {
                    return D;
                }
            }
        }
        assert(false);
    }

    function arrayClone(uint256[N_COINS] memory a) internal pure returns (uint256[N_COINS] memory res) {
        for (uint256 i = 0; i < N_COINS; ++i) {
            res[i] = a[i];
        }
    }
}
