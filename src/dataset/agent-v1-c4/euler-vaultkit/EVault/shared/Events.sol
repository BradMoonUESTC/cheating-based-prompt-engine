// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

/// @title Events
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Contract implementing EVault's events
abstract contract Events {
    // ERC20

    /// @notice Transfer an ERC20 token balance
    /// @param from Sender address
    /// @param to Receiver address
    /// @param value Tokens sent
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice Set an ERC20 approval
    /// @param owner Address granting approval to spend tokens
    /// @param spender Address receiving approval to spend tokens
    /// @param value Amount of tokens approved to spend
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // ERC4626

    /// @notice Deposit assets into an ERC4626 vault
    /// @param sender Address initiating the deposit
    /// @param owner Address holding the assets
    /// @param assets Amount of assets deposited
    /// @param shares Amount of shares minted as receipt for the deposit
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    /// @notice Withdraw from an ERC4626 vault
    /// @param sender Address initiating the withdrawal
    /// @param receiver Address receiving the assets
    /// @param owner Address holding the shares
    /// @param assets Amount of assets sent to the receiver
    /// @param shares Amount of shares burned
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    // EVault

    /// @notice New EVault is initialized
    /// @param creator Address designated as the vault's creator
    /// @param asset The underlying asset of the vault
    /// @param dToken Address of the sidecar debt token
    event EVaultCreated(address indexed creator, address indexed asset, address dToken);

    /// @notice Log the current vault status
    /// @param totalShares Sum of all shares
    /// @param totalBorrows Sum of all borrows in assets
    /// @param accumulatedFees Interest fees accrued in the accumulator
    /// @param cash The amount of assets held by the vault directly
    /// @param interestAccumulator Current interest accumulator in ray
    /// @param interestRate Current interest rate, which will be applied during the next fee accrual
    /// @param timestamp Current block's timestamp
    event VaultStatus(
        uint256 totalShares,
        uint256 totalBorrows,
        uint256 accumulatedFees,
        uint256 cash,
        uint256 interestAccumulator,
        uint256 interestRate,
        uint256 timestamp
    );

    /// @notice Increase account's debt
    /// @param account Address adding liability
    /// @param assets Amount of debt added in assets
    event Borrow(address indexed account, uint256 assets);

    /// @notice Decrease account's debt
    /// @param account Address repaying the debt
    /// @param assets Amount of debt removed in assets
    event Repay(address indexed account, uint256 assets);

    /// @notice Account's debt was increased due to interest
    /// @param account Address being charged interest
    /// @param assets Amount of debt added in assets
    event InterestAccrued(address indexed account, uint256 assets);

    /// @notice Liquidate unhealthy account
    /// @param liquidator Address executing the liquidation
    /// @param violator Address holding an unhealthy borrow
    /// @param collateral Address of the asset seized
    /// @param repayAssets Amount of debt in assets transferred from violator to liquidator
    /// @param yieldBalance Amount of collateral asset's balance transferred from violator to liquidator
    event Liquidate(
        address indexed liquidator,
        address indexed violator,
        address collateral,
        uint256 repayAssets,
        uint256 yieldBalance
    );

    /// @notice Take on debt from another account
    /// @param from Account from which the debt is taken
    /// @param to Account taking on the debt
    /// @param assets Amount of debt transferred in assets
    event PullDebt(address from, address to, uint256 assets);

    /// @notice Socialize debt after liquidating all of the unhealthy account's collateral
    /// @param account Address holding an unhealthy borrow
    /// @param assets Amount of debt socialized among all of the share holders
    event DebtSocialized(address indexed account, uint256 assets);

    /// @notice Split the accumulated fees between the governor and the protocol
    /// @param sender Address initializing the conversion
    /// @param protocolReceiver Address receiving the protocol's share of the fees
    /// @param governorReceiver Address receiving the governor's share of the fees
    /// @param protocolShares Amount of shares transferred to the protocol receiver
    /// @param governorShares Amount of shares transferred to the governor receiver
    event ConvertFees(
        address indexed sender,
        address indexed protocolReceiver,
        address indexed governorReceiver,
        uint256 protocolShares,
        uint256 governorShares
    );

    /// @notice Enable or disable balance tracking for the account
    /// @param account Address which enabled or disabled balance tracking
    /// @param status True if balance tracking was enabled, false otherwise
    event BalanceForwarderStatus(address indexed account, bool status);
}
