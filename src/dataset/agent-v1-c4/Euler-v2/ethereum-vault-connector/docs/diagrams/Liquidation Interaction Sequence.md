```mermaid
sequenceDiagram
    actor Violator
    Note right of Violator: Dotted lines mean optional
    actor Liquidator
    participant Controller Vault
    participant EVC
    participant Collateral Vault
    participant Price Oracle

    Liquidator->>Controller Vault: liquidate(violator, collateral vault)
    Controller Vault->>EVC: call(liquidate(violator, collateral vault))
    EVC->>EVC: set the execution context
    EVC->>Controller Vault: liquidate(violator, collateral vault)

    Controller Vault->>EVC: liquidator = getCurrentOnBehalfOfAccount(address(vault))
    Controller Vault->>Controller Vault: is liquidator liquidating itself?
    Controller Vault->>EVC: isControllerEnabled(violator, Controller Vault)
    Controller Vault->>Controller Vault: controller must be enabled
    Controller Vault->>EVC: isAccountStatusCheckDeferred(violator)
    Controller Vault->>Controller Vault: account status check cannot be deferred
    Controller Vault-->>Controller Vault: is the requested collateral accepted and trusted?
    Controller Vault->>Controller Vault: is the violator indeed in violation?
    Controller Vault-->>Controller Vault: vault snapshot
    Controller Vault->>Controller Vault: liquidation logic
    Controller Vault->>Controller Vault: transfer the liability from the violator to the liquidator
    Controller Vault-->>Controller Vault: if Controller Vault == Collateral Vault, seize violator's collateral

    critical
        Controller Vault-->>EVC: if Controller Vault != Collateral Vault, controlCollateral(collateral vault, violator, transfer(liquidator, collateral amount))
        EVC->>Collateral Vault: transfer(liquidator, collateral amount)
        Collateral Vault->>EVC: getCurrentOnBehalfOfAccount(address(0))
        Collateral Vault-->>Collateral Vault: vault snapshot
        Collateral Vault->>Collateral Vault: transfer logic
        Collateral Vault->>EVC: requireAccountStatusCheck(violator)
        Collateral Vault->>EVC: requireVaultStatusCheck()
    end

    Controller Vault-->>EVC: if collateral trusted or action can be verified, forgiveAccountStatusCheck(violator)
    Controller Vault->>EVC: requireAccountStatusCheck(liquidator)
    Controller Vault->>EVC: requireVaultStatusCheck()

    critical
        opt if check not forgiven
            EVC->>Controller Vault: checkAccountStatus(violator, collaterals)
            Controller Vault->>Controller Vault: is msg.sender EVC?
            Controller Vault->>EVC: areChecksInProgress()
            Controller Vault-->>Price Oracle: getQuote()
            Controller Vault->>Controller Vault: determine violator's liquidity
        end

        EVC->>Controller Vault: checkAccountStatus(liquidator, collaterals)
        Controller Vault->>Controller Vault: is msg.sender EVC?
        Controller Vault->>EVC: areChecksInProgress()
        Controller Vault-->>Collateral Vault: balanceOf()
        Controller Vault-->>Price Oracle: getQuote()
        Controller Vault->>Controller Vault: determine liquidator's liquidity

        EVC->>Collateral Vault: checkVaultStatus()
        Collateral Vault->>Collateral Vault: is msg.sender EVC?
        Collateral Vault->>EVC: areChecksInProgress()
        Collateral Vault->>Collateral Vault: determine vault's health

        EVC->>Controller Vault: checkVaultStatus()
        Controller Vault->>Controller Vault: is msg.sender EVC?
        Controller Vault->>EVC: areChecksInProgress()
        Controller Vault->>Controller Vault: determine vault's health
    end

    EVC->>EVC: clear the execution context
```