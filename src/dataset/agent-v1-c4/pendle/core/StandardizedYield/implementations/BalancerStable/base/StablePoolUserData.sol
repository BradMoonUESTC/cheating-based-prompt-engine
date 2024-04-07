// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

library StablePoolUserData {
    enum JoinKind {
        INIT,
        EXACT_TOKENS_IN_FOR_BPT_OUT,
        TOKEN_IN_FOR_EXACT_BPT_OUT
    }
    enum ExitKind {
        EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
        BPT_IN_FOR_EXACT_TOKENS_OUT
    }

    function exactTokensInForBptOut(
        bytes memory self
    ) internal pure returns (uint256[] memory amountsIn, uint256 minBPTAmountOut) {
        (, amountsIn, minBPTAmountOut) = abi.decode(self, (JoinKind, uint256[], uint256));
    }

    function exactBptInForTokenOut(bytes memory self) internal pure returns (uint256 bptAmountIn, uint256 tokenIndex) {
        (, bptAmountIn, tokenIndex) = abi.decode(self, (ExitKind, uint256, uint256));
    }
}
