// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../../interfaces/GMX/IGMXVault.sol";
import "../../../../interfaces/GMX/IVaultPriceFeed.sol";

abstract contract GLPPreviewHelper {
    // Based on Vault functions

    IGMXVault public immutable vault;
    address internal immutable usdg;
    uint256 public constant PRICE_PRECISION = 10 ** 30;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    constructor(address _vaultAddress) {
        vault = IGMXVault(_vaultAddress);
        usdg = vault.usdg();
    }

    function _buyUSDG(address _token, uint256 tokenAmount) internal view returns (uint256) {
        tokenAmount = __transferIn(_token, tokenAmount);
        assert(tokenAmount > 0);

        uint256 price = vault.getMinPrice(_token);

        uint256 usdgAmount = (tokenAmount * price) / PRICE_PRECISION;
        usdgAmount = vault.adjustForDecimals(usdgAmount, _token, usdg);
        require(usdgAmount > 0, "preview buyUSDG: usdgAmount must be > 0");

        uint256 feeBasisPoints = __getFeeBasisPoints(
            _token,
            usdgAmount,
            0,
            vault.mintBurnFeeBasisPoints(),
            vault.taxBasisPoints(),
            true
        );
        uint256 amountAfterFees = __collectSwapFees(_token, tokenAmount, feeBasisPoints);
        uint256 mintAmount = (amountAfterFees * price) / PRICE_PRECISION;
        mintAmount = vault.adjustForDecimals(mintAmount, _token, usdg);

        return mintAmount;
    }

    function _sellUSDG(address _token, uint256 usdgAmount) internal view returns (uint256) {
        usdgAmount = __transferIn(usdg, usdgAmount);
        assert(usdgAmount > 0);

        uint256 redemptionAmount = vault.getRedemptionAmount(_token, usdgAmount);
        require(redemptionAmount > 0, "preview sellUSDG: redemptionAmount must be > 0");

        uint256 feeBasisPoints = __getFeeBasisPoints(
            _token,
            usdgAmount,
            usdgAmount,
            vault.mintBurnFeeBasisPoints(),
            vault.taxBasisPoints(),
            false
        );
        uint256 amountOut = __collectSwapFees(_token, redemptionAmount, feeBasisPoints);
        require(amountOut > 0, "preview sellUSDG: amountOut must be > 0");

        return amountOut;
    }

    function __transferIn(address _token, uint256 _amount) private view returns (uint256) {
        uint256 prevBalance = vault.tokenBalances(_token);
        uint256 nextBalance = IERC20(_token).balanceOf(address(vault)) + _amount;

        return nextBalance - prevBalance;
    }

    function __collectSwapFees(
        address /*_token*/,
        uint256 _amount,
        uint256 _feeBasisPoints
    ) private pure returns (uint256) {
        uint256 afterFeeAmount = (_amount * (BASIS_POINTS_DIVISOR - _feeBasisPoints)) / (BASIS_POINTS_DIVISOR);
        return afterFeeAmount;
    }

    function __getFeeBasisPoints(
        address _token,
        uint256 _usdgDelta,
        uint256 _burnedUsdg,
        uint256 _feeBasisPoints,
        uint256 _taxBasisPoints,
        bool _increment
    ) private view returns (uint256) {
        if (!vault.hasDynamicFees()) {
            return _feeBasisPoints;
        }

        uint256 initialAmount = vault.usdgAmounts(_token);
        initialAmount = (initialAmount >= _burnedUsdg) ? initialAmount - _burnedUsdg : 0;

        uint256 nextAmount = initialAmount + _usdgDelta;
        if (!_increment) {
            nextAmount = _usdgDelta > initialAmount ? 0 : initialAmount - _usdgDelta;
        }

        uint256 targetAmount = __getTargetUsdgAmount(_token, _burnedUsdg);
        if (targetAmount == 0) {
            return _feeBasisPoints;
        }

        uint256 initialDiff = initialAmount > targetAmount
            ? initialAmount - targetAmount
            : targetAmount - initialAmount;
        uint256 nextDiff = nextAmount > targetAmount ? nextAmount - targetAmount : targetAmount - nextAmount;

        // action improves relative asset balance
        if (nextDiff < initialDiff) {
            uint256 rebateBps = (_taxBasisPoints * initialDiff) / targetAmount;
            return rebateBps > _feeBasisPoints ? 0 : _feeBasisPoints - rebateBps;
        }

        uint256 averageDiff = (initialDiff + nextDiff) / 2;
        if (averageDiff > targetAmount) {
            averageDiff = targetAmount;
        }
        uint256 taxBps = (_taxBasisPoints * averageDiff) / targetAmount;
        return _feeBasisPoints + taxBps;
    }

    function __getTargetUsdgAmount(address _token, uint256 _burnedUsdg) private view returns (uint256) {
        uint256 supply = IERC20(usdg).totalSupply() - _burnedUsdg;
        if (supply == 0) {
            return 0;
        }
        uint256 weight = vault.tokenWeights(_token);
        return (weight * supply) / vault.totalTokenWeights();
    }
}
