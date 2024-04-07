# Audit note GLP SY

Our goal is to support SY for the GLP token of GMX.

The SY supports mint-and-staking GLP with a whitelisted token (ETH, WBTC, etc) or receiving staked GLP from user.

## Overview

- _The main contract_ for the SY is: `PendleGlpSY.sol`.  
  This contract contains the main logic ofk all SY operations, except GMX's Vault-related logic for preview functions. This part is contained in the abstract preview contract, which is inherited by the main contract.

* _The preview contract_ is: `GMXPreviewHelper.sol`.  
  This contract simulates the logic of GMX's Vault to preview buying/selling USDG during deposit/redeem.

## About PendleGlpSY

A typical, ordinary SY contract.

- _Constructor_: Initialize global variables and approve whitelisted tokens to GMX's GlpManager, which would pull tokens in from the SY contract when minting GLP.
  - There are two routers: _rewardRouter_ is used for claiming rewards,, _glpRouter_ is used to deposit/redeem; hence the two global router variables.
- _Deposit_:
  - In case of receiving staked GLP, then staked GLP is already pulled in with \_transferIn() in SYBase.
    **Note:** StakedGLP (sGLP) is a helper contract by GMX for users to transfer their staked GLP between each other, where staking and unstaking happen behind the scenes. It is not an ERC20 token, but it behaves similar enough to one so that we treat it is ERC20 in the contract.
  - Otherwise, use GlpRewardRouter to mint and stake.
- _Redeem_: Same as deposit, reversed. If user redeems in staked GLP, \_transferOut() is used for staked GLP.
- _Exchange rate_: The SY directly wraps GLP, so the exchange rate is always 1.
- _Preview deposit_: Mimics the logic of _\_addLiquidity()_ in GMX's GlpManager. The functions needs to preview _buyUSDG()_ of GMX's Vault, which is mimicked in GMXPreviewHelper.
- _Preview redeem_: Mimics the logic of _\_removeLiquidity()_ in GMX's GlpManager. The functions needs to preview _sellUSDG()_ of GMX's Vault, which is also mimicked in GMXPreviewHelper.
- _Get tokens in/out_: Queries whitelisted tokens from GMX's Vault, then return them along with staked GLP and native ETH.
- _Check valid token in/out_: Calls _whitelistedTokens()_ from GMX's Vault to check.

## About GMXPreviewHelper

This contract's purpose is to support preview for _buyUSDG()_ and _sellUSDG()_ functions from GMX's Vault. The contracts has two view functions _buyUSDG()_ and _sellUSDG()_ which mimics their respective Vault counterpart's logic.

About _buyUSDG()_:

- First, _tokenAmount_ is calculated with \_transferIn(), which should give the same as the corresponding Vault function.
- _updateCumulativeFundingRate()_ in Vault should not impact amount out, so this is ignored.
- For _price_ and _usdgAmount_, the Vault view functions used in Vault's buyUSDG() should behave the same as during actual redeeming, so they are called directly from Vault.
- For _feeBasisPoints_, _getFeeBasisPoints()_ also behave the same as Vault, becacuse the extra parameter _\_burnedUsdg_ = 0 which has no affect on the return value.
- For _amountAfterFees_, see _\_collectSwapFees()_ below.
- Finally, _mintAmount_ is calculated normally.

About _sellUSDG()_:

- Again, first _usdgAmount_ is calculated.
- _updateCumulativeFundingRate()_ in Vault should not impact amount out, so this is ignored.
- We directly call Vault's getRedemptionAmount() to calculate _redemptionAmount_. Although _useSwapPricing_ is set to true earlier in Vault's _sellUSDG()_, and _getRedemptionAmount()_ calls _getMaxPrice()_, which then calls priceFeed's _getPrice()_ with _useSwapPricing_ as a parameter, this parameter is then ignored in _getPrice()_. So we can ignore _useSwapPricing_, and Vault's _getRedemptionAmount()_ called in preview should behave the same as actual redeem.
- Next, _decreaseUsdgAmount() and USDG's \_burn()_ are called. This affects USDG balances, which would later affect _getFeeBasisPoints()_.
- _poolAmounts_ and _tokenBalances_ should not affect the amount out, so _\_decreasePoolAmount()_ and _\_updateTokenBalance()_ are ignored.
- For _feeBasisPoints_, we need _getFeeBasisPoints()_. But _usdgAmounts[\_token]_ has been decreased by _usdgAmount_, so we account for this by adding parameter _\_burnedUsdg_ in our "fake" _getFeeBasisPoints()_.
- Finally, _amountOut_ is calculated with _\_collectSwapFees()_.

Other helper functions:

- _\_transferIn()_: Mimics Vault's counterpart, should return the same value.
- _\_collectSwapFees()_: In Vault, this function only changes _feeReserves_ which does not affect deposit/redeem, so we only need the _afterFeeAmount_.
- _getFeeBasisPoints()_: Since USDG balances are affected in _sellUSDG()_, another parameter _\_burnedUsdg_ is introduced to account for this decrease in USDG. Namely, this affects:
  - _initialAmount_: The new _usdgAmount[\_token]_ is different, which is calculated here similar to Vault's decreaseUsdgAmount().
  - _getTargetUsdgAmount()_: The formula for the target amount concerns the total supply of USDG, which is affected by _burn()_ in _sellUSDG()_. This is accounted for in our "fake" _getTargetUsdgAmount()_, which takes _\_burnedUsdg_ as parameter and uses it to calculate the real _supply_.

In our tests, all - intermediate and final return - values perfectly matches between Vault's functions and our replicas.
