// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Errors} from "../helpers/Errors.sol";
import {StorageSlot} from "./StorageSlot.sol";
import {DataTypes} from "../types/DataTypes.sol";

library ValidationLogic {
    function validateSwapParams(
        bool _isSwapEnabled,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        mapping(address => bool) storage whitelistedTokens
    ) internal view {
        validate(_isSwapEnabled, Errors.VAULT_SWAPS_NOT_ENABLED);
        validate(
            whitelistedTokens[_tokenIn],
            Errors.VAULT_TOKEN_IN_NOT_WHITELISTED
        );
        validate(
            whitelistedTokens[_tokenOut],
            Errors.VAULT_TOKEN_OUT_NOT_WHITELISTED
        );
        validate(_tokenIn != _tokenOut, Errors.VAULT_INVALID_TOKENS);
        validate(_amountIn > 0, Errors.VAULT_INVALID_AMOUNT_IN);
    }

    function validateIncreasePositionParams(
        bool _isLeverageEnabled,
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) internal view {
        validateLeverage(_isLeverageEnabled);
        validateGasPrice();
        validateRouter(_account);
        validateTokens(_collateralToken, _indexToken, _isLong);
    }

    function validateDecreasePositionParams(address _account) internal view {
        validateGasPrice();
        validateRouter(_account);
    }

    function validateGasPrice() internal view {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        if (ps.maxGasPrice == 0) {
            return;
        }
        validate(
            tx.gasprice <= ps.maxGasPrice,
            Errors.VAULT_MAX_GAS_PRICE_EXCEEDED
        );
    }

    function validateWhitelistedToken(address _token) internal view {
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        validate(
            ts.whitelistedTokens[_token],
            Errors.VAULT_TOKEN_IN_NOT_WHITELISTED
        );
    }

    function validateBufferAmount(address _token) internal view {
        DataTypes.PositionStorage storage ps = StorageSlot
            .getVaultPositionStorage();
        validate(
            ps.poolAmounts[_token] >= ps.bufferAmounts[_token],
            Errors.VAULT_POOL_AMOUNT_LESS_THAN_BUFFER_AMOUNT
        );
    }

    function validateManager() internal view {
        DataTypes.PermissionStorage storage ps = StorageSlot
            .getVaultPermissionStorage();
        if (ps.inManagerMode) {
            validate(ps.isManager[msg.sender], Errors.VAULT_FORBIDDEN);
        }
    }

    function validateTokens(
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) internal view {
        DataTypes.TokenConfigSotrage storage ts = StorageSlot
            .getVaultTokenConfigStorage();
        if (_isLong) {
            validate(
                _collateralToken == _indexToken,
                Errors.VAULT_MISMATCHED_TOKENS
            );
            validate(
                ts.whitelistedTokens[_collateralToken],
                Errors.VAULT_COLLATERAL_TOKEN_NOT_WHITELISTED
            );
            validate(
                !ts.stableTokens[_collateralToken],
                Errors.VAULT_COLLATERAL_TOKEN_MUST_BE_STABLE_TOKEN
            );
            return;
        }

        validate(
            ts.whitelistedTokens[_collateralToken],
            Errors.VAULT_COLLATERAL_TOKEN_NOT_WHITELISTED
        );
        validate(
            ts.stableTokens[_collateralToken],
            Errors.VAULT_COLLATERAL_TOKEN_MUST_BE_STABLE_TOKEN
        );
        validate(
            !ts.stableTokens[_indexToken],
            Errors.VAULT_INDEX_TOKEN_MUST_NOT_BE_STABLE_TOKEN
        );
        validate(
            ts.shortableTokens[_indexToken],
            Errors.VAULT_INDEX_TOKEN_NOT_SHORTABLE
        );
    }

    function validatePosition(
        uint256 _size,
        uint256 _collateral
    ) internal pure {
        if (_size == 0) {
            validate(
                _collateral == 0,
                Errors.VAULT_COLLATERAL_SHOULD_BE_WITHDRAWN
            );
            return;
        }
        validate(
            _size >= _collateral,
            Errors.VAULT_SIZE_MUST_BE_MORE_THAN_COLLATERAL
        );
    }

    function validateRouter(address _account) internal view {
        DataTypes.AddressStorage storage addrs = StorageSlot
            .getVaultAddressStorage();
        DataTypes.PermissionStorage storage ps = StorageSlot
            .getVaultPermissionStorage();
        if (msg.sender == _account) {
            return;
        }
        if (msg.sender == addrs.router) {
            return;
        }
        validate(
            ps.approvedRouters[_account][msg.sender],
            Errors.VAULT_INVALID_MSG_SENDER
        );
    }

    function validateLeverage(bool _isLeverageEnabled) internal pure {
        validate(_isLeverageEnabled, Errors.VAULT_LEVERAGE_NOT_ENABLED);
    }

    function validateIncreasePosition(
        address /* _account */,
        address /* _collateralToken */,
        address /* _indexToken */,
        uint256 /* _sizeDelta */,
        bool /* _isLong */
    ) internal pure {
        // no additional validations
    }

    function validateDecreasePosition(
        address /* _account */,
        address /* _collateralToken */,
        address /* _indexToken */,
        uint256 /* _collateralDelta */,
        uint256 /* _sizeDelta */,
        bool /* _isLong */,
        address /* _receiver */
    ) internal pure {
        // no additional validations
    }

    function validate(bool _condition, string memory _errorCode) internal pure {
        require(_condition, _errorCode);
    }
}
