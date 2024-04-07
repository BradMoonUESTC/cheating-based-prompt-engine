// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../../../interfaces/Balancer/IVault.sol";
import "../../../../../interfaces/Balancer/IBalancerFees.sol";
import "../../../../../interfaces/Balancer/IBalancerStablePreview.sol";

abstract contract StablePreviewBase is IBalancerStablePreview {
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant FEE_COLLECTOR = 0xce88686553686DA562CE7Cea497CE749DA109f9F;

    enum PoolBalanceChangeKind {
        JOIN,
        EXIT
    }

    struct PoolBalanceChange {
        IAsset[] assets;
        uint256[] limits;
        bytes userData;
        bool useInternalBalance;
    }

    function joinPoolPreview(
        bytes32 poolId,
        address sender,
        address recipient,
        IVault.JoinPoolRequest memory request,
        bytes memory data
    ) external view returns (uint256 amountBptOut) {
        amountBptOut = _joinOrExit(
            PoolBalanceChangeKind.JOIN,
            poolId,
            sender,
            payable(recipient),
            _toPoolBalanceChange(request),
            data
        );
    }

    function exitPoolPreview(
        bytes32 poolId,
        address sender,
        address recipient,
        IVault.ExitPoolRequest memory request,
        bytes memory data
    ) external view returns (uint256 amountTokenOut) {
        amountTokenOut = _joinOrExit(
            PoolBalanceChangeKind.EXIT,
            poolId,
            sender,
            recipient,
            _toPoolBalanceChange(request),
            data
        );
    }

    function _joinOrExit(
        PoolBalanceChangeKind kind,
        bytes32 poolId,
        address sender,
        address recipient,
        PoolBalanceChange memory change,
        bytes memory data
    ) private view returns (uint256 amountBptOrTokensOut) {
        IERC20[] memory tokens = _translateToIERC20(change.assets);
        (uint256[] memory balances, uint256 lastChangeBlock) = _validateTokensAndGetBalances(poolId, tokens);

        amountBptOrTokensOut = _callPoolBalanceChange(
            kind,
            poolId,
            sender,
            recipient,
            change,
            balances,
            lastChangeBlock,
            data
        );
    }

    function _callPoolBalanceChange(
        PoolBalanceChangeKind kind,
        bytes32 poolId,
        address sender,
        address recipient,
        PoolBalanceChange memory change,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        bytes memory data
    ) private view returns (uint256 amountsChanged) {
        if (kind == PoolBalanceChangeKind.JOIN) {
            amountsChanged = onJoinPool(
                poolId,
                sender,
                recipient,
                balances,
                lastChangeBlock,
                _getProtocolSwapFeePercentage(),
                change.userData,
                data
            );
        } else {
            amountsChanged = onExitPool(
                poolId,
                sender,
                recipient,
                balances,
                lastChangeBlock,
                _getProtocolSwapFeePercentage(),
                change.userData,
                data
            );
        }
    }

    function _getProtocolSwapFeePercentage() private view returns (uint256) {
        return IBalancerFees(FEE_COLLECTOR).getSwapFeePercentage();
    }

    function _validateTokensAndGetBalances(
        bytes32 poolId,
        IERC20[] memory //expectedTokens
    ) private view returns (uint256[] memory, uint256) {
        (, uint256[] memory balances, uint256 lastChangeBlock) = IVault(BALANCER_VAULT).getPoolTokens(poolId);
        return (balances, lastChangeBlock);
    }

    function _translateToIERC20(IAsset[] memory assets) internal pure returns (IERC20[] memory) {
        IERC20[] memory tokens = new IERC20[](assets.length);
        for (uint256 i = 0; i < assets.length; ++i) {
            tokens[i] = _translateToIERC20(assets[i]);
        }
        return tokens;
    }

    function _translateToIERC20(IAsset asset) internal pure returns (IERC20) {
        return address(asset) == address(0) ? IERC20(WETH) : IERC20(address(asset));
    }

    function _toPoolBalanceChange(
        IVault.JoinPoolRequest memory request
    ) private pure returns (PoolBalanceChange memory change) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            change := request
        }
    }

    function _toPoolBalanceChange(
        IVault.ExitPoolRequest memory request
    ) private pure returns (PoolBalanceChange memory change) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            change := request
        }
    }

    function onJoinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData,
        bytes memory data
    ) internal view virtual returns (uint256 bptAmountOut);

    function onExitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] memory balances,
        uint256 lastChangeBlock,
        uint256 protocolSwapFeePercentage,
        bytes memory userData,
        bytes memory data
    ) internal view virtual returns (uint256 amountTokenOut);
}
