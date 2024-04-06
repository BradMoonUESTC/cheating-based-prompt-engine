// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

// Interfaces
import {CollateralTracker} from "@contracts/CollateralTracker.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Partial} from "@tokens/interfaces/IERC20Partial.sol";
import {SemiFungiblePositionManager} from "@contracts/SemiFungiblePositionManager.sol";
// OpenZeppelin libraries
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title InteractionHelper - contains helper functions for external interactions such as approvals.
/// @notice Used to delegate logic with multiple external calls.
/// @dev Generally employed when there is a need to save or reuse bytecode size
// on a core contract (calls take a significant amount of logic).
/// @author Axicon Labs Limited
library InteractionHelper {
    /// @notice Function that performs approvals on behalf of the PanopticPool for CollateralTracker and SemiFungiblePositionManager.
    /// @param sfpm The SemiFungiblePositionManager being approved for both token0 and token1
    /// @param ct0 The CollateralTracker (token0) being approved for token0
    /// @param ct1 The CollateralTracker (token1) being approved for token1
    /// @param token0 The token0 (in Uniswap) being approved for
    /// @param token1 The token1 (in Uniswap) being approved for
    function doApprovals(
        SemiFungiblePositionManager sfpm,
        CollateralTracker ct0,
        CollateralTracker ct1,
        address token0,
        address token1
    ) external {
        // Approve transfers of Panoptic Pool funds by SFPM
        IERC20Partial(token0).approve(address(sfpm), type(uint256).max);
        IERC20Partial(token1).approve(address(sfpm), type(uint256).max);

        // Approve transfers of Panoptic Pool funds by Collateral token
        IERC20Partial(token0).approve(address(ct0), type(uint256).max);
        IERC20Partial(token1).approve(address(ct1), type(uint256).max);
    }

    /// @notice Computes the name of a CollateralTracker based on the token composition and fee of the underlying Uniswap Pool.
    /// @dev Some tokens do not have proper symbols so error handling is required - this logic takes up significant bytecode size, which is why it is in a library.
    /// @param token0 The token0 in the Uniswap Pool
    /// @param token1 The token1 in the Uniswap Pool
    /// @param isToken0 Whether the collateral token computing the name is for token0 or token1
    /// @param fee The fee of the Uniswap pool in basis points
    /// @param prefix A constant string appended to the start of the token name
    /// @return The complete name of the collateral token calling this function
    function computeName(
        address token0,
        address token1,
        bool isToken0,
        uint24 fee,
        string memory prefix
    ) external view returns (string memory) {
        // get the underlying token symbols
        // it's not guaranteed that they support the metadata extension
        // so we need to let them fail and return placeholder if not
        string memory symbol0;
        string memory symbol1;
        try IERC20Metadata(token0).symbol() returns (string memory _symbol) {
            symbol0 = _symbol;
        } catch {
            symbol0 = "???";
        }
        try IERC20Metadata(token1).symbol() returns (string memory _symbol) {
            symbol1 = _symbol;
        } catch {
            symbol1 = "???";
        }
        unchecked {
            return
                string.concat(
                    prefix,
                    " ",
                    isToken0 ? symbol0 : symbol1,
                    " LP on ",
                    symbol0,
                    "/",
                    symbol1,
                    " ",
                    Strings.toString(fee),
                    "bps"
                );
        }
    }

    /// @notice Returns symbol as prefixed symbol of underlying token.
    /// @param token The address of the underlying token used to compute the symbol
    /// @param prefix A constant string appended to the symbol of the underlying token to create the final symbol
    /// @return The symbol of the token
    function computeSymbol(
        address token,
        string memory prefix
    ) external view returns (string memory) {
        // not guaranteed that token supports metadada extension
        // so we need to let call fail and return placeholder if not
        try IERC20Metadata(token).symbol() returns (string memory tokenSymbol) {
            return string.concat(prefix, tokenSymbol);
        } catch {
            return string.concat(prefix, "???");
        }
    }

    /// @notice Returns decimals of underlying token (0 if not present).
    /// @param token The address of the underlying token used to compute the decimals
    /// @return The decimals of the token
    function computeDecimals(address token) external view returns (uint8) {
        // not guaranteed that token supports metadada extension
        // so we need to let call fail and return placeholder if not
        try IERC20Metadata(token).decimals() returns (uint8 _decimals) {
            return _decimals;
        } catch {
            return 0;
        }
    }
}
