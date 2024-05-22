// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
// Interfaces

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

// Base Contracts
import {HandlerAggregator} from "../HandlerAggregator.t.sol";

/// @title VaultModuleInvariants
/// @notice Implements Invariants for the protocol
/// @dev Inherits HandlerAggregator to check actions in assertion testing mode
abstract contract VaultModuleInvariants is HandlerAggregator {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                        VAULT SIMPLE                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_VM_INVARIANT_A() internal {
        assertGe(IERC20(address(eTST.asset())).balanceOf(address(eTST)), eTST.cash(), VM_INVARIANT_A);
    }

    function assert_VM_INVARIANT_C() internal {
        if (eTST.totalAssets() == 0) {
            assertEq(eTST.totalSupply(), 0, VM_INVARIANT_C);
        }
        if (eTST.totalSupply() == 0) {
            assertEq(eTST.totalAssets(), 0, VM_INVARIANT_C);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      ERC4626: ASSETS                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_ERC4626_ASSETS_INVARIANT_A() internal {
        try eTST.asset() {}
        catch {
            fail(ERC4626_ASSETS_INVARIANT_A);
        }
    }

    function assert_ERC4626_ASSETS_INVARIANT_B() internal {
        try eTST.totalAssets() returns (uint256 totalAssets) {
            totalAssets;
        } catch {
            fail(ERC4626_ASSETS_INVARIANT_B);
        }
    }

    function assert_ERC4626_ASSETS_INVARIANT_C() internal {
        uint256 _assets = _getRandomValue(_maxAssets());
        uint256 shares;
        bool notFirstLoop;

        for (uint256 i; i < NUMBER_OF_ACTORS; i++) {
            vm.prank(actorAddresses[i]);
            uint256 tempShares = eTST.convertToShares(_assets);

            // Compare the shares with the previous iteration expect the first one
            if (notFirstLoop) {
                assertEq(shares, tempShares, ERC4626_ASSETS_INVARIANT_C);
            } else {
                shares = tempShares;
                notFirstLoop = true;
            }
        }
    }

    function assert_ERC4626_ASSETS_INVARIANT_D() internal {
        uint256 _shares = _getRandomValue(_maxShares());
        uint256 assets;
        bool notFirstLoop;

        for (uint256 i; i < NUMBER_OF_ACTORS; i++) {
            vm.prank(actorAddresses[i]);
            uint256 tempAssets = eTST.convertToAssets(_shares);

            // Compare the shares with the previous iteration expect the first one
            if (notFirstLoop) {
                assertEq(assets, tempAssets, ERC4626_ASSETS_INVARIANT_D);
            } else {
                assets = tempAssets;
                notFirstLoop = true;
            }
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      ERC4626: DEPOSIT                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_ERC4626_DEPOSIT_INVARIANT_A(address _account) internal {
        try eTST.maxDeposit(_account) {}
        catch {
            fail(ERC4626_DEPOSIT_INVARIANT_A);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      ERC4626: MINT                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_ERC4626_MINT_INVARIANT_A(address _account) internal {
        try eTST.maxMint(_account) {}
        catch {
            fail(ERC4626_MINT_INVARIANT_A);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    ERC4626: WITHDRAW                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_ERC4626_WITHDRAW_INVARIANT_A(address _account) internal {
        try eTST.maxWithdraw(_account) {}
        catch {
            fail(ERC4626_WITHDRAW_INVARIANT_A);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    ERC4626: REDEEM                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function assert_ERC4626_REDEEM_INVARIANT_A(address _account) internal {
        try eTST.maxRedeem(_account) {}
        catch {
            fail(ERC4626_REDEEM_INVARIANT_A);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         UTILS                                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _maxShares() internal view returns (uint256 shares) {
        shares = eTST.totalSupply();
        shares = shares == 0 ? 1 : shares;
    }

    function _maxAssets() internal view returns (uint256 assets) {
        assets = eTST.totalAssets();
        assets = assets == 0 ? 1 : assets;
    }

    function _max_withdraw(address from) internal view virtual returns (uint256) {
        return eTST.convertToAssets(eTST.balanceOf(from)); // may be different from
            // maxWithdraw(from)
    }

    function _max_redeem(address from) internal view virtual returns (uint256) {
        return eTST.balanceOf(from); // may be different from maxRedeem(from)
    }
}
