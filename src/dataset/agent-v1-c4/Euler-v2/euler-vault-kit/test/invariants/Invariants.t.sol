// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Invariant Contracts
import {BaseInvariants} from "./invariants/BaseInvariants.t.sol";
import {TokenModuleInvariants} from "./invariants/TokenModuleInvariants.t.sol";
import {VaultModuleInvariants} from "./invariants/VaultModuleInvariants.t.sol";
import {BorrowingModuleInvariants} from "./invariants/BorrowingModuleInvariants.t.sol";
import {LiquidationModuleInvariants} from "./invariants/LiquidationModuleInvariants.t.sol";
import {InterestInvariants} from "./invariants/InterestInvariants.t.sol";
/// @title Invariants
/// @notice Wrappers for the protocol invariants implemented in each invariants contract
/// @dev recognised by Echidna when property mode is activated
/// @dev Inherits BaseInvariants that inherits HandlerAggregator

abstract contract Invariants is
    BaseInvariants,
    TokenModuleInvariants,
    VaultModuleInvariants,
    BorrowingModuleInvariants,
    LiquidationModuleInvariants,
    InterestInvariants
{
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     BASE INVARIANTS                                       //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function echidna_BASE_INVARIANT() public returns (bool) {
        assert_BASE_INVARIANT_A();
        assert_BASE_INVARIANT_B();
        return true;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                 TOKEN MODULE INVARIANTS                                   //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function echidna_TM_INVARIANT() public monotonicTimestamp returns (bool) {
        assert_TM_INVARIANT_A();

        uint256 _sumBalanceOf;
        for (uint256 i; i < NUMBER_OF_ACTORS; i++) {
            assert_TM_INVARIANT_B(actorAddresses[i]);
            _sumBalanceOf += eTST.balanceOf(actorAddresses[i]);
        }
        assert_TM_INVARIANT_C(_sumBalanceOf);
        return true;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       VAULT MODULE                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function echidna_VM_INVARIANT() public monotonicTimestamp returns (bool) {
        assert_VM_INVARIANT_A();
        //assert_VM_INVARIANT_C();
        return true;
    }

    function echidna_ERC4626_ASSETS_INVARIANT() public monotonicTimestamp returns (bool) {
        assert_ERC4626_ASSETS_INVARIANT_A();
        assert_ERC4626_ASSETS_INVARIANT_B();
        assert_ERC4626_ASSETS_INVARIANT_C();
        assert_ERC4626_ASSETS_INVARIANT_D();
        return true;
    }

    function echidna_ERC4626_ACTIONS_INVARIANT() public monotonicTimestamp returns (bool) {
        for (uint256 i; i < NUMBER_OF_ACTORS; i++) {
            assert_ERC4626_DEPOSIT_INVARIANT_A(actorAddresses[i]);
            assert_ERC4626_MINT_INVARIANT_A(actorAddresses[i]);
            assert_ERC4626_WITHDRAW_INVARIANT_A(actorAddresses[i]);
            assert_ERC4626_REDEEM_INVARIANT_A(actorAddresses[i]);
        }
        return true;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                BORROWING MODULE INVARIANTS                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function echidna_BM_INVARIANT() public monotonicTimestamp returns (bool) {
        for (uint256 i; i < NUMBER_OF_ACTORS; i++) {
            assert_BM_INVARIANT_A(actorAddresses[i]);
            assert_BM_INVARIANT_J(actorAddresses[i]);
        }
        assert_BM_INVARIANT_B();
        return true;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                        INTEREST INVARIANTS                                //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function echidna_I_INVARIANT() public monotonicTimestamp returns (bool) {
        assert_I_INVARIANT_A();
        assert_I_INVARIANT_B();
        assert_I_INVARIANT_D();
        return true;
    }
}
