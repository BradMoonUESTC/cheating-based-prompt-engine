// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../../../libraries/math/PMath.sol";
import "../../../../../interfaces/Curve/ITriCrvPool.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library Curve3CrvPoolHelper {
    using PMath for uint256;

    uint256 internal constant N_COINS = 3;
    uint256 internal constant PRECISION = 10 ** 18;
    uint256 internal constant RATE_0 = 1000000000000000000;
    uint256 internal constant RATE_1 = 1000000000000000000000000000000;
    uint256 internal constant RATE_2 = 1000000000000000000000000000000;
    uint256 internal constant FEE_DENOMINATOR = 10 ** 10;

    address internal constant LP = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address internal constant POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    // previewDeposit at the end of the file

    function preview3CrvRedeem(address tokenOut, uint256 amountSharesToRedeem) internal view returns (uint256) {
        return ITriCrvPool(POOL).calc_withdraw_one_coin(amountSharesToRedeem, _get3CrvTokenIndex(tokenOut).Int128());
    }

    function deposit3Crv(address tokenIn, uint256 amountTokenToDeposit) internal returns (uint256) {
        uint256 balBefore = IERC20(LP).balanceOf(address(this));
        ITriCrvPool(POOL).add_liquidity(_getTokenAmounts(tokenIn, amountTokenToDeposit), 0);
        uint256 balAfter = IERC20(LP).balanceOf(address(this));
        return balAfter - balBefore;
    }

    function redeem3Crv(address tokenOut, uint256 amountSharesToRedeem) internal returns (uint256) {
        uint256 balBefore = IERC20(tokenOut).balanceOf(address(this));
        ITriCrvPool(POOL).remove_liquidity_one_coin(amountSharesToRedeem, _get3CrvTokenIndex(tokenOut).Int128(), 0);
        uint256 balAfter = IERC20(tokenOut).balanceOf(address(this));
        return balAfter - balBefore;
    }

    function _getTokenAmounts(address token, uint256 amount) internal pure returns (uint256[N_COINS] memory res) {
        res[_get3CrvTokenIndex(token)] = amount;
    }

    function _get3CrvTokenIndex(address token) internal pure returns (uint256) {
        if (token == DAI) return 0;
        if (token == USDC) return 1;
        if (token == USDT) return 2;
        revert("Pendle3CrvHelper: not valid token");
    }

    function is3CrvToken(address token) internal pure returns (bool) {
        return (token == DAI || token == USDC || token == USDT);
    }

    function get_virtual_price() internal view returns (uint256) {
        return ITriCrvPool(POOL).get_virtual_price();
    }

    // ----------------- Forking StableSwap3Pool's calculation -----------------

    // fork of StableSwap3Pool.vy
    function preview3CrvDeposit(
        address token,
        uint256 amount
    ) internal view returns (uint256 netLpOut, uint256 new_virtual_price) {
        uint256[N_COINS] memory amounts = _getTokenAmounts(token, amount);
        uint256[N_COINS] memory self_balances = _getBalances();

        uint256[N_COINS] memory fees;
        uint256 _fee = (ITriCrvPool(POOL).fee() * N_COINS) / (4 * (N_COINS - 1));
        uint256 _admin_fee = ITriCrvPool(POOL).admin_fee();
        uint256 amp = ITriCrvPool(POOL).A();

        uint256 token_supply = IERC20(LP).totalSupply();
        // Initial invariant
        uint256 D0 = 0;
        uint256[N_COINS] memory old_balances = arrayClone(self_balances);
        D0 = get_D_mem(old_balances, amp);

        uint256[N_COINS] memory new_balances = arrayClone(old_balances);

        for (uint256 i = 0; i < N_COINS; ++i) {
            new_balances[i] += amounts[i];
        }

        uint256 D1 = get_D_mem(new_balances, amp);
        assert(D1 > D0);

        // We need to recalculate the invariant accounting for fees
        // to calculate fair user's share
        uint256 D2 = D1;
        for (uint256 i = 0; i < N_COINS; ++i) {
            uint256 ideal_balance = (D1 * old_balances[i]) / D0;
            uint256 difference = 0;
            if (ideal_balance > new_balances[i]) {
                difference = ideal_balance - new_balances[i];
            } else {
                difference = new_balances[i] - ideal_balance;
            }
            fees[i] = (_fee * difference) / FEE_DENOMINATOR;
            self_balances[i] = new_balances[i] - ((fees[i] * _admin_fee) / FEE_DENOMINATOR);
            new_balances[i] -= fees[i];
            D2 = get_D_mem(new_balances, amp);
        }

        netLpOut = (token_supply * (D2 - D0)) / D0;
        new_virtual_price = _get_virtual_price_with_balances(self_balances, token_supply + netLpOut);
    }

    function _get_virtual_price_with_balances(
        uint256[N_COINS] memory balances,
        uint256 token_supply
    ) internal view returns (uint256) {
        uint256 amp = ITriCrvPool(POOL).A();
        uint256 D = get_D_mem(balances, amp);
        return (D * PRECISION) / token_supply;
    }

    function get_D_mem(uint256[N_COINS] memory balances, uint256 amp) internal pure returns (uint256) {
        return get_D(_xp_mem(balances), amp);
    }

    function _xp_mem(uint256[N_COINS] memory balances) internal pure returns (uint256[N_COINS] memory) {
        uint256[N_COINS] memory result;
        result[0] = (RATE_0 * balances[0]) / PRECISION;
        result[1] = (RATE_1 * balances[1]) / PRECISION;
        result[2] = (RATE_2 * balances[2]) / PRECISION;

        return result;
    }

    function get_D(uint256[N_COINS] memory _xp, uint256 _amp) internal pure returns (uint256) {
        uint256 S = 0;
        for (uint256 k = 0; k < N_COINS; ++k) S += _xp[k];
        if (S == 0) return 0;

        uint256 Dprev = 0;
        uint256 D = S;
        uint256 Ann = _amp * N_COINS;

        for (uint256 _i = 0; _i < 255; ++_i) {
            uint256 D_P = D;
            for (uint256 k = 0; k < N_COINS; ++k) {
                D_P = (D_P * D) / (_xp[k] * N_COINS);
            }
            Dprev = D;
            D = ((Ann * S + D_P * N_COINS) * D) / (((Ann - 1) * D) + (N_COINS + 1) * D_P);

            if (D > Dprev) {
                if (D - Dprev <= 1) {
                    break;
                }
            } else {
                if (Dprev - D <= 1) {
                    break;
                }
            }
        }
        return D;
    }

    function _getBalances() internal view returns (uint256[N_COINS] memory balances) {
        balances[0] = ITriCrvPool(POOL).balances(0);
        balances[1] = ITriCrvPool(POOL).balances(1);
        balances[2] = ITriCrvPool(POOL).balances(2);
    }

    function arrayClone(uint256[N_COINS] memory a) internal pure returns (uint256[N_COINS] memory res) {
        for (uint256 i = 0; i < N_COINS; ++i) {
            res[i] = a[i];
        }
    }
}
