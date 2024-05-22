// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title InvariantsSpec
/// @notice Invariants specification for the protocol
/// @dev Contains pseudo code and description for the invariants in the protocol
/// @dev Invariants for Token, Vault, Borrowing, Liquidations mechanics
abstract contract InvariantsSpec {
    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          BASE                                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    string constant BASE_INVARIANT_A = "BASE_INVARIANT_A: reentrancyLock == REENTRANCY_UNLOCKED";

    string constant BASE_INVARIANT_B = "BASE_INVARIANT_B: snapshot should be reseted after every action";

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                          INTERNAL INVARIANTS: LOW-LEVEL FUNCTIONS                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    string constant INTERNAL_INVARIANT_A = "INTERNAL_INVARIANT_A: initOperation is called in low-level functions";

    string constant INTERNAL_INVARIANT_B = "INTERNAL_INVARIANT_B: vault status check is deferred in low-level functions";

    string constant INTERNAL_INVARIANT_C = "INTERNAL_INVARIANT_C: account status check is deferred if needed";

    string constant INTERNAL_INVARIANT_D = "INTERNAL_INVARIANT_D: controller is enabled if needed";

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       TOKEN MODULE                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    string constant TM_INVARIANT_A = "TM_INVARIANT_A: totalSupply = sum of all minted shares + accumulatedFees";

    string constant TM_INVARIANT_B = "TM_INVARIANT_B: balanceOf(actor) == sum of all shares owned by address";

    string constant TM_INVARIANT_C = "TM_INVARIANT_C: totalSupply == sum of balanceOf(actors) + accumulatedFees";

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       VAULT MODULE                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    string constant VM_INVARIANT_A = "VM_INVARIANT_A: underlying.balanceOf(vault) >= cash";

    string constant VM_INVARIANT_B =
        "VM_INVARIANT_B: If totalSupply increases new totalSupply must be less than or equal to supply cap";

    string constant VM_INVARIANT_C = "VM_INVARIANT_C: If totalAssets == 0 <=> totalSupply == 0";

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                              VAULT MODULE: ERC4626 INVARIANTS                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice ASSETS

    string constant ERC4626_ASSETS_INVARIANT_A = "ERC4626_ASSETS_INVARIANT_A: asset MUST NOT revert";

    string constant ERC4626_ASSETS_INVARIANT_B = "ERC4626_ASSETS_INVARIANT_B: totalAssets MUST NOT revert";

    string constant ERC4626_ASSETS_INVARIANT_C =
        "ERC4626_ASSETS_INVARIANT_C: convertToShares MUST NOT show any variations depending on the caller";

    string constant ERC4626_ASSETS_INVARIANT_D =
        "ERC4626_ASSETS_INVARIANT_D: convertToAssets MUST NOT show any variations depending on the caller";

    /// @notice DEPOSIT

    string constant ERC4626_DEPOSIT_INVARIANT_A = "ERC4626_DEPOSIT_INVARIANT_A: maxDeposit MUST NOT revert";

    string constant ERC4626_DEPOSIT_INVARIANT_B =
        "ERC4626_DEPOSIT_INVARIANT_B: previewDeposit MUST return close to and no more than shares minted at deposit if called in the same transaction";

    /// @notice MINT

    string constant ERC4626_MINT_INVARIANT_A = "ERC4626_MINT_INVARIANT_A: maxMint MUST NOT revert";

    string constant ERC4626_MINT_INVARIANT_B =
        "ERC4626_MINT_INVARIANT_B: previewMint MUST return close to and no fewer than assets deposited at mint if called in the same transaction";

    /// @notice WITHDRAW

    string constant ERC4626_WITHDRAW_INVARIANT_A = "ERC4626_WITHDRAW_INVARIANT_A: maxWithdraw MUST NOT revert";

    string constant ERC4626_WITHDRAW_INVARIANT_B =
        "ERC4626_WITHDRAW_INVARIANT_B: previewWithdraw MUST return close to and no fewer than shares burned at withdraw if called in the same transaction";

    /// @notice REDEEM

    string constant ERC4626_REDEEM_INVARIANT_A = "ERC4626_REDEEM_INVARIANT_A: maxRedeem MUST NOT revert";

    string constant ERC4626_REDEEM_INVARIANT_B =
        "ERC4626_REDEEM_INVARIANT_B: previewRedeem MUST return close to and no more than assets redeemed at redeem if called in the same transaction";

    /// @notice ROUNDTRIP

    string constant ERC4626_ROUNDTRIP_INVARIANT_A = "ERC4626_ROUNDTRIP_INVARIANT_A: redeem(deposit(a)) <= a";

    string constant ERC4626_ROUNDTRIP_INVARIANT_B =
        "ERC4626_ROUNDTRIP_INVARIANT_B: s = deposit(a) s' = withdraw(a) s' >= s";

    string constant ERC4626_ROUNDTRIP_INVARIANT_C = "ERC4626_ROUNDTRIP_INVARIANT_C: deposit(redeem(s)) <= s";

    string constant ERC4626_ROUNDTRIP_INVARIANT_D = "ERC4626_ROUNDTRIP_INVARIANT_D: a = redeem(s) a' = mint(s) a' >= a";

    string constant ERC4626_ROUNDTRIP_INVARIANT_E = "ERC4626_ROUNDTRIP_INVARIANT_E: withdraw(mint(s)) >= s";

    string constant ERC4626_ROUNDTRIP_INVARIANT_F = "ERC4626_ROUNDTRIP_INVARIANT_F: a = mint(s) a' = redeem(s) a' <= a";

    string constant ERC4626_ROUNDTRIP_INVARIANT_G = "ERC4626_ROUNDTRIP_INVARIANT_G: mint(withdraw(a)) >= a";

    string constant ERC4626_ROUNDTRIP_INVARIANT_H =
        "ERC4626_ROUNDTRIP_INVARIANT_H: s = withdraw(a) s' = deposit(a) s' <= s";

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     BORROWING MODULE                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    string constant BM_INVARIANT_A = "BM_INVARIANT_A: totalBorrowed >= any account owed balance";

    string constant BM_INVARIANT_B = "BM_INVARIANT_B: totalBorrowed = sum of all user debt";

    string constant BM_INVARIANT_C = "BM_INVARIANT_C: sum of all user debt == 0 <=> totalBorrowed == 0";

    string constant BM_INVARIANT_D = "BM_INVARIANT_D: User liability should always decrease after repayment";

    string constant BM_INVARIANT_E = "BM_INVARIANT_E: Unhealthy users can not borrow";

    string constant BM_INVARIANT_F = "BM_INVARIANT_F: If theres at least one borrow, the asset.balanceOf(vault) > 0"; // Discarded

    string constant BM_INVARIANT_G =
        "BM_INVARIANT_G: a user should always be able to withdraw all if there is no outstanding debt";

    string constant BM_INVARIANT_H =
        "BM_INVARIANT_H: If totalBorrows increases new totalBorrows must be less than or equal to borrow cap";

    string constant BM_INVARIANT_I = "BM_INVARIANT_I: Controller cannot be disabled if there is any liability";

    string constant BM_INVARIANT_J = "BM_INVARIANT_J: relation between debtOf and debtOfExact";

    string constant BM_INVARIANT_K = "BM_INVARIANT_K: Functions that wont operate when user is unhealthy";

    string constant BM_INVARIANT_L = "BM_INVARIANT_L: Functions that can operate when user is unhealthy";

    string constant BM_INVARIANT_M = "";

    string constant BM_INVARIANT_N1 =
        "BM_INVARIANT_N1: borrow/deposit(x) => repayWithShares(x) users shouldn't gain any asset";

    string constant BM_INVARIANT_N2 =
        "BM_INVARIANT_N2: borrow/deposit(x) => repayWithShares(x) users debt shouldn't decrease";

    string constant BM_INVARIANT_O = "BM_INVARIANT_O: debt(user) != 0 => collateralValue != 0";

    string constant BM_INVARIANT_P = "BM_INVARIANT_P: a user can always repay debt in full";

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                          INTEREST                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    string constant I_INVARIANT_A = "I_INVARIANT_A: interestFee should be in range";

    string constant I_INVARIANT_B = "I_INVARIANT_B: lastInterestAccumulatorUpdate <= block.timestamp";

    string constant I_INVARIANT_C = "I_INVARIANT_C: updateMarket increases the value of totalBorrows";

    string constant I_INVARIANT_D = "I_INVARIANT_D: interestRate in range";

    string constant I_INVARIANT_E = "I_INVARIANT_E: Interest rate accumulator monotonically increases";

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    LIQUIDATION MODULE                                    //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    string constant LM_INVARIANT_A = "LM_INVARIANT_A: Liquidation can only succed if violator is unhealthy";

    string constant LM_INVARIANT_B = "LM_INVARIANT_B: debtSocialization == 0 => exchangeRate <= exchangeRate' ";

    string constant LM_INVARIANT_C = "LM_INVARIANT_C: Only a liquidation can leave a healthy account unhealthy";

    string constant LM_INVARIANT_D =
        "LM_INVARIANT_D: Only liquidations can deteriorate health score of an already unhealthy account";
}
