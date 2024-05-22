// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Dispatch} from "./Dispatch.sol";

/// @title EVault
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice This contract implements an EVC enabled lending vault
/// @dev The responsibility of this contract is call routing. Select functions are embedded, while most are delegated to the modules
contract EVault is Dispatch {
    constructor(Integrations memory integrations, DeployedModules memory modules) Dispatch(integrations, modules) {}


    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     INITIALIZATION                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function initialize(address proxyCreator) public virtual override use(MODULE_INITIALIZE) {}



    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         TOKEN                                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function name() public view virtual override useView(MODULE_TOKEN) returns (string memory) {}

    function symbol() public view virtual override useView(MODULE_TOKEN) returns (string memory) {}

    function decimals() public view virtual override returns (uint8) { return super.decimals(); }

    function totalSupply() public view virtual override useView(MODULE_TOKEN) returns (uint256) {}

    function balanceOf(address account) public view virtual override returns (uint256) { return super.balanceOf(account); }

    function allowance(address holder, address spender) public view virtual override returns (uint256) { return super.allowance(holder, spender); }


    function transfer(address to, uint256 amount) public virtual override callThroughEVC returns (bool) { return super.transfer(to, amount); }

    function transferFrom(address from, address to, uint256 amount) public virtual override callThroughEVC returns (bool) { return super.transferFrom(from, to, amount); }

    function approve(address spender, uint256 amount) public virtual override returns (bool) { return super.approve(spender, amount); }

    function transferFromMax(address from, address to) public virtual override callThroughEVC returns (bool) { return super.transferFromMax(from, to); }



    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                         VAULT                                             //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function asset() public view virtual override returns (address) { return super.asset(); }

    function totalAssets() public view virtual override useView(MODULE_VAULT) returns (uint256) {}

    function convertToAssets(uint256 shares) public view virtual override returns (uint256) { return super.convertToAssets(shares); }

    function convertToShares(uint256 assets) public view virtual override returns (uint256) { return super.convertToShares(assets); }

    function maxDeposit(address account) public view virtual override useView(MODULE_VAULT) returns (uint256) {}

    function previewDeposit(uint256 assets) public view virtual override useView(MODULE_VAULT) returns (uint256) {}

    function maxMint(address account) public view virtual override useView(MODULE_VAULT) returns (uint256) {}

    function previewMint(uint256 shares) public view virtual override useView(MODULE_VAULT) returns (uint256) {}

    function maxWithdraw(address owner) public view virtual override useView(MODULE_VAULT) returns (uint256) {}

    function previewWithdraw(uint256 assets) public view virtual override useView(MODULE_VAULT) returns (uint256) {}

    function maxRedeem(address owner) public view virtual override useView(MODULE_VAULT) returns (uint256) {}

    function previewRedeem(uint256 shares) public view virtual override useView(MODULE_VAULT) returns (uint256) {}

    function accumulatedFees() public view virtual override returns (uint256) { return super.accumulatedFees(); }

    function accumulatedFeesAssets() public view virtual override returns (uint256) { return super.accumulatedFeesAssets(); }

    function creator() public view virtual override useView(MODULE_VAULT) returns (address) {}


    function deposit(uint256 amount, address receiver) public virtual override callThroughEVC returns (uint256) { return super.deposit(amount, receiver); }

    function mint(uint256 amount, address receiver) public virtual override callThroughEVC use(MODULE_VAULT) returns (uint256) {}

    function withdraw(uint256 amount, address receiver, address owner) public virtual override callThroughEVC use(MODULE_VAULT) returns (uint256) {}

    function redeem(uint256 amount, address receiver, address owner) public virtual override callThroughEVC use(MODULE_VAULT) returns (uint256) {}

    function skim(uint256 amount, address receiver) public virtual override callThroughEVC use(MODULE_VAULT) returns (uint256) {}



    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                        BORROWING                                          //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function totalBorrows() public view virtual override useView(MODULE_BORROWING) returns (uint256) {}

    function totalBorrowsExact() public view virtual override useView(MODULE_BORROWING) returns (uint256) {}

    function cash() public view virtual override useView(MODULE_BORROWING) returns (uint256) {}

    function debtOf(address account) public view virtual override returns (uint256) { return super.debtOf(account); }

    function debtOfExact(address account) public view virtual override useView(MODULE_BORROWING) returns (uint256) {}

    function interestRate() public view virtual override returns (uint256) { return super.interestRate(); }

    function interestAccumulator() public view virtual override useView(MODULE_BORROWING) returns (uint256) {}

    function dToken() public view virtual override useView(MODULE_BORROWING) returns (address) {}


    function borrow(uint256 amount, address receiver) public virtual override callThroughEVC use(MODULE_BORROWING) returns (uint256) {}

    function repay(uint256 amount, address receiver) public virtual override callThroughEVC use(MODULE_BORROWING) returns (uint256) {}

    function repayWithShares(uint256 amount, address receiver) public virtual override callThroughEVC use(MODULE_BORROWING) returns (uint256 shares, uint256 debt) {}

    function pullDebt(uint256 amount, address from) public virtual override callThroughEVC use(MODULE_BORROWING) returns (uint256) {}

    function flashLoan(uint256 amount, bytes calldata data) public virtual override use(MODULE_BORROWING) {}

    function touch() public virtual override callThroughEVC use(MODULE_BORROWING) {}



    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     LIQUIDATION                                           //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function checkLiquidation(address liquidator, address violator, address collateral) public view virtual override useView(MODULE_LIQUIDATION) returns (uint256 maxRepay, uint256 maxYield) {}

    function liquidate(address violator, address collateral, uint256 repayAssets, uint256 minYieldBalance) public virtual override callThroughEVC use(MODULE_LIQUIDATION) {}



    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                    RISK MANAGEMENT                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function accountLiquidity(address account, bool liquidation) public view virtual override useView(MODULE_RISKMANAGER) returns (uint256 collateralValue, uint256 liabilityValue) {}

    function accountLiquidityFull(address account, bool liquidation) public view virtual override useView(MODULE_RISKMANAGER) returns (address[] memory collaterals, uint256[] memory collateralValues, uint256 liabilityValue) {}


    function disableController() public virtual override use(MODULE_RISKMANAGER) {}

    function checkAccountStatus(address account, address[] calldata collaterals) public virtual override returns (bytes4) { return super.checkAccountStatus(account, collaterals); }

    function checkVaultStatus() public virtual override returns (bytes4) { return super.checkVaultStatus(); }



    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                   BALANCE TRACKING                                        //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function balanceTrackerAddress() public view virtual override useView(MODULE_BALANCE_FORWARDER) returns (address) {}

    function balanceForwarderEnabled(address account) public view virtual override useView(MODULE_BALANCE_FORWARDER) returns (bool) {}


    function enableBalanceForwarder() public virtual override use(MODULE_BALANCE_FORWARDER) {}

    function disableBalanceForwarder() public virtual override use(MODULE_BALANCE_FORWARDER) {}



    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                     GOVERNANCE                                            //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function governorAdmin() public view virtual override useView(MODULE_GOVERNANCE) returns (address) {}

    function feeReceiver() public view virtual override useView(MODULE_GOVERNANCE) returns (address) {}

    function interestFee() public view virtual override returns (uint16) { return super.interestFee(); }

    function interestRateModel() public view virtual override useView(MODULE_GOVERNANCE) returns (address) {}

    function protocolConfigAddress() public view virtual override useView(MODULE_GOVERNANCE) returns (address) {}

    function protocolFeeShare() public view virtual override useView(MODULE_GOVERNANCE) returns (uint256) {}

    function protocolFeeReceiver() public view virtual override useView(MODULE_GOVERNANCE) returns (address) {}

    function caps() public view virtual override useView(MODULE_GOVERNANCE) returns (uint16 supplyCap, uint16 borrowCap) {}

    function LTVBorrow(address collateral) public view virtual override useView(MODULE_GOVERNANCE) returns (uint16) {}

    function LTVLiquidation(address collateral) public view virtual override useView(MODULE_GOVERNANCE) returns (uint16) {}

    function LTVFull(address collateral) public view virtual override useView(MODULE_GOVERNANCE) returns (uint16 borrowLTV, uint16 liquidationLTV, uint16 initialLiquidationLTV, uint48 targetTimestamp, uint32 rampDuration) {}

    function LTVList() public view virtual override useView(MODULE_GOVERNANCE) returns (address[] memory) {}

    function maxLiquidationDiscount() public view virtual override useView(MODULE_GOVERNANCE) returns (uint16) {}

    function liquidationCoolOffTime() public view virtual override useView(MODULE_GOVERNANCE) returns (uint16) {}

    function hookConfig() public view virtual override useView(MODULE_GOVERNANCE) returns (address, uint32) {}

    function configFlags() public view virtual override useView(MODULE_GOVERNANCE) returns (uint32) {}

    function EVC() public view virtual override useView(MODULE_GOVERNANCE) returns (address) {}

    function unitOfAccount() public view virtual override useView(MODULE_GOVERNANCE) returns (address) {}

    function oracle() public view virtual override useView(MODULE_GOVERNANCE) returns (address) {}

    function permit2Address() public view virtual override useView(MODULE_GOVERNANCE) returns (address) {}


    function convertFees() public virtual override callThroughEVC use(MODULE_GOVERNANCE) {}

    function setGovernorAdmin(address newGovernorAdmin) public virtual override use(MODULE_GOVERNANCE) {}

    function setFeeReceiver(address newFeeReceiver) public virtual override use(MODULE_GOVERNANCE) {}

    function setHookConfig(address newHookTarget, uint32 newHookedOps) public virtual override use(MODULE_GOVERNANCE) {}

    function setLTV(address collateral, uint16 borrowLTV, uint16 liquidationLTV, uint32 rampDuration) public virtual override use(MODULE_GOVERNANCE) {}

    function clearLTV(address collateral) public virtual override use(MODULE_GOVERNANCE) {}

    function setMaxLiquidationDiscount(uint16 newDiscount) public virtual override use(MODULE_GOVERNANCE) {}

    function setLiquidationCoolOffTime(uint16 newCoolOffTime) public virtual override use(MODULE_GOVERNANCE) {}

    function setInterestRateModel(address newModel) public virtual override use(MODULE_GOVERNANCE) {}

    function setConfigFlags(uint32 newConfigFlags) public virtual override use(MODULE_GOVERNANCE) {}

    function setCaps(uint16 supplyCap, uint16 borrowCap) public virtual override use(MODULE_GOVERNANCE) {}

    function setInterestFee(uint16 newFee) public virtual override use(MODULE_GOVERNANCE) {}
}
