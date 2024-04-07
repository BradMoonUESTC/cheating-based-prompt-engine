// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../interfaces/IPYieldToken.sol";
import "../../interfaces/IPPrincipalToken.sol";
import "../../interfaces/IStandardizedYield.sol";

abstract contract CallbackHelper {
    enum ActionType {
        SwapExactSyForYt,
        SwapYtForSy,
        SwapExactYtForPt,
        SwapExactPtForYt
    }

    /// ------------------------------------------------------------
    /// SwapExactSyForYt
    /// ------------------------------------------------------------

    function _encodeSwapExactSyForYt(address receiver, IPYieldToken YT) internal pure returns (bytes memory res) {
        res = new bytes(96);
        uint256 actionType = uint256(ActionType.SwapExactSyForYt);

        assembly {
            mstore(add(res, 32), actionType)
            mstore(add(res, 64), receiver)
            mstore(add(res, 96), YT)
        }
    }

    function _decodeSwapExactSyForYt(bytes calldata data) internal pure returns (address receiver, IPYieldToken YT) {
        assembly {
            // first 32 bytes is ActionType
            receiver := calldataload(add(data.offset, 32))
            YT := calldataload(add(data.offset, 64))
        }
    }

    /// ------------------------------------------------------------
    /// SwapYtForSy (common encode & decode)
    /// ------------------------------------------------------------

    function _encodeSwapYtForSy(address receiver, IPYieldToken YT) internal pure returns (bytes memory res) {
        res = new bytes(96);
        uint256 actionType = uint256(ActionType.SwapYtForSy);

        assembly {
            mstore(add(res, 32), actionType)
            mstore(add(res, 64), receiver)
            mstore(add(res, 96), YT)
        }
    }

    function _decodeSwapYtForSy(bytes calldata data) internal pure returns (address receiver, IPYieldToken YT) {
        assembly {
            // first 32 bytes is ActionType
            receiver := calldataload(add(data.offset, 32))
            YT := calldataload(add(data.offset, 64))
        }
    }

    function _encodeSwapExactYtForPt(
        address receiver,
        uint256 netPtOut,
        IPPrincipalToken PT,
        IPYieldToken YT
    ) internal pure returns (bytes memory res) {
        res = new bytes(160);
        uint256 actionType = uint256(ActionType.SwapExactYtForPt);

        assembly {
            mstore(add(res, 32), actionType)
            mstore(add(res, 64), receiver)
            mstore(add(res, 96), netPtOut)
            mstore(add(res, 128), PT)
            mstore(add(res, 160), YT)
        }
    }

    function _decodeSwapExactYtForPt(
        bytes calldata data
    ) internal pure returns (address receiver, uint256 netPtOut, IPPrincipalToken PT, IPYieldToken YT) {
        assembly {
            // first 32 bytes is ActionType
            receiver := calldataload(add(data.offset, 32))
            netPtOut := calldataload(add(data.offset, 64))
            PT := calldataload(add(data.offset, 96))
            YT := calldataload(add(data.offset, 128))
        }
    }

    function _encodeSwapExactPtForYt(
        address receiver,
        uint256 exactPtIn,
        uint256 minYtOut,
        IPYieldToken YT
    ) internal pure returns (bytes memory res) {
        res = new bytes(160);
        uint256 actionType = uint256(ActionType.SwapExactPtForYt);

        assembly {
            mstore(add(res, 32), actionType)
            mstore(add(res, 64), receiver)
            mstore(add(res, 96), exactPtIn)
            mstore(add(res, 128), minYtOut)
            mstore(add(res, 160), YT)
        }
    }

    function _decodeSwapExactPtForYt(
        bytes calldata data
    ) internal pure returns (address receiver, uint256 exactPtIn, uint256 minYtOut, IPYieldToken YT) {
        assembly {
            // first 32 bytes is ActionType
            receiver := calldataload(add(data.offset, 32))
            exactPtIn := calldataload(add(data.offset, 64))
            minYtOut := calldataload(add(data.offset, 96))
            YT := calldataload(add(data.offset, 128))
        }
    }

    /// ------------------------------------------------------------
    /// Misc functions
    /// ------------------------------------------------------------
    function _getActionType(bytes calldata data) internal pure returns (ActionType actionType) {
        assembly {
            actionType := calldataload(data.offset)
        }
    }
}
