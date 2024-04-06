
NB: This report has been created using [Solidity-Metrics](https://github.com/Consensys/solidity-metrics)
<sup>

# Solidity Metrics for Scoping for panoptic-labs - panoptic-v1-core-private

## Table of contents

- [Solidity Metrics for Scoping for panoptic-labs - panoptic-v1-core-private](#solidity-metrics-for-scoping-for-panoptic-labs---panoptic-v1-core-private)
  - [Table of contents](#table-of-contents)
  - [Scope](#scope)
    - [Source Units in Scope](#source-units-in-scope)
        - [Legend](#legend)
    - [Out of Scope](#out-of-scope)
    - [Excluded Source Units](#excluded-source-units)
  - [Report](#report)
  - [Overview](#overview)
    - [Inline Documentation](#inline-documentation)
    - [Components](#components)
    - [Exposed Functions](#exposed-functions)
    - [StateVariables](#statevariables)
    - [Capabilities](#capabilities)
    - [Dependencies / External Imports](#dependencies--external-imports)
        - [Contract Summary](#contract-summary)

## <span id=t-scope>Scope</span>

This section lists files that are in scope for the metrics report.

- **Project:** `Scoping for panoptic-labs - panoptic-v1-core-private`
- **Included Files:** 
20
- **Excluded Files:** 
30
- **Project analysed:** `https://github.com/panoptic-labs/panoptic-v1-core-private` (`@dcb619e9a18465ff17422a7f0a8db2a619e6c5fe`)

### <span id=t-source-Units-in-Scope>Source Units in Scope</span>

Source Units Analyzed: **`20`**<br>
Source Units in Scope: **`20`** (**100%**)

| Type | File   | Logic Contracts | Interfaces | Lines | nLines | nSLOC | Comment Lines | Complex. Score | Capabilities |
| ---- | ------ | --------------- | ---------- | ----- | ------ | ----- | ------------- | -------------- | ------------ | 
| 📝 | contracts/CollateralTracker.sol | 1 | **** | 1650 | 1540 | 682 | 669 | 415 | **<abbr title='Initiates ETH Value Transfer'>📤</abbr><abbr title='Unchecked Blocks'>Σ</abbr>** |
| 📝 | contracts/PanopticFactory.sol | 1 | **** | 423 | 405 | 198 | 143 | 103 | **<abbr title='Unchecked Blocks'>Σ</abbr>** |
| 📝 | contracts/PanopticPool.sol | 1 | **** | 1981 | 1819 | 992 | 597 | 597 | **<abbr title='Uses Hash-Functions'>🧮</abbr><abbr title='Unchecked Blocks'>Σ</abbr>** |
| 📝 | contracts/SemiFungiblePositionManager.sol | 1 | **** | 1569 | 1446 | 601 | 697 | 352 | **<abbr title='Uses Hash-Functions'>🧮</abbr><abbr title='Unchecked Blocks'>Σ</abbr>** |
| 📚 | contracts/libraries/CallbackLib.sol | 1 | **** | 39 | 35 | 18 | 13 | 4 | **** |
| 📚 | contracts/libraries/Constants.sol | 1 | **** | 23 | 23 | 9 | 9 | 6 | **** |
| 📚 | contracts/libraries/Errors.sol | 1 | **** | 112 | 112 | 36 | 43 | 1 | **** |
| 📚 | contracts/libraries/FeesCalc.sol | 1 | **** | 209 | 194 | 71 | 115 | 41 | **<abbr title='Unchecked Blocks'>Σ</abbr>** |
| 📚 | contracts/libraries/InteractionHelper.sol | 1 | **** | 116 | 101 | 57 | 38 | 38 | **<abbr title='TryCatch Blocks'>♻️</abbr><abbr title='Unchecked Blocks'>Σ</abbr>** |
| 📚 | contracts/libraries/Math.sol | 1 | **** | 782 | 763 | 398 | 304 | 531 | **<abbr title='Uses Assembly'>🖥</abbr><abbr title='Unchecked Blocks'>Σ</abbr>** |
| 📚 | contracts/libraries/PanopticMath.sol | 1 | **** | 967 | 892 | 498 | 308 | 445 | **<abbr title='Uses Hash-Functions'>🧮</abbr><abbr title='Unchecked Blocks'>Σ</abbr>** |
| 📚 | contracts/libraries/SafeTransferLib.sol | 1 | **** | 77 | 77 | 33 | 37 | 113 | **<abbr title='Uses Assembly'>🖥</abbr>** |
| 🎨 | contracts/multicall/Multicall.sol | 1 | **** | 37 | 37 | 18 | 15 | 37 | **<abbr title='Uses Assembly'>🖥</abbr><abbr title='Payable Functions'>💰</abbr><abbr title='DelegateCall'>👥</abbr><abbr title='Unchecked Blocks'>Σ</abbr>** |
| 🎨 | contracts/tokens/ERC1155Minimal.sol | 1 | **** | 241 | 226 | 100 | 91 | 61 | **<abbr title='Unchecked Blocks'>Σ</abbr>** |
| 🎨 | contracts/tokens/ERC20Minimal.sol | 1 | **** | 147 | 147 | 52 | 66 | 20 | **<abbr title='Unchecked Blocks'>Σ</abbr>** |
| 🔍 | contracts/tokens/interfaces/IDonorNFT.sol | **** | 1 | 20 | 13 | 4 | 7 | 3 | **** |
| 🔍 | contracts/tokens/interfaces/IERC20Partial.sol | **** | 1 | 28 | 16 | 3 | 19 | 7 | **** |
| 📚 | contracts/types/LeftRight.sol | 1 | **** | 302 | 279 | 133 | 102 | 144 | **<abbr title='Unchecked Blocks'>Σ</abbr>** |
| 📚 | contracts/types/LiquidityChunk.sol | 1 | **** | 194 | 175 | 72 | 88 | 33 | **<abbr title='Unchecked Blocks'>Σ</abbr>** |
| 📚 | contracts/types/TokenId.sol | 1 | **** | 600 | 559 | 264 | 246 | 158 | **<abbr title='Unchecked Blocks'>Σ</abbr>** |
| 📝📚🔍🎨 | **Totals** | **18** | **2** | **9517**  | **8859** | **4239** | **3607** | **3109** | **<abbr title='Uses Assembly'>🖥</abbr><abbr title='Payable Functions'>💰</abbr><abbr title='Initiates ETH Value Transfer'>📤</abbr><abbr title='DelegateCall'>👥</abbr><abbr title='Uses Hash-Functions'>🧮</abbr><abbr title='TryCatch Blocks'>♻️</abbr><abbr title='Unchecked Blocks'>Σ</abbr>** |

##### <span>Legend</span>
<ul>
<li> <b>Lines</b>: total lines of the source unit </li>
<li> <b>nLines</b>: normalized lines of the source unit (e.g. normalizes functions spanning multiple lines) </li>
<li> <b>SLOC</b>: source lines of code</li>
<li> <b>Comment Lines</b>: lines containing single or block comments </li>
<li> <b>Complexity Score</b>: a custom complexity score derived from code statements that are known to introduce code complexity (branches, loops, calls, external interfaces, ...) </li>
</ul>

### <span id=t-out-of-scope>Out of Scope</span>

### <span id=t-out-of-scope-excluded-source-units>Excluded Source Units</span>
Source Units Excluded: **`28`**

| File |
| ---- |
| /test/foundry/types/harnesses/TokenIdHarness.sol |
| /test/foundry/types/harnesses/LiquidityChunkHarness.sol |
| /test/foundry/types/harnesses/LeftRightHarness.sol |
| /test/foundry/types/TokenId.t.sol |
| /test/foundry/types/LiquidityChunk.t.sol |
| /test/foundry/types/LeftRight.t.sol |
| /test/foundry/tokens/ERC1155Minimal.t.sol |
| /test/foundry/testUtils/ReentrancyMocks.sol |
| /test/foundry/testUtils/PriceMocks.sol |
| /test/foundry/testUtils/PositionUtils.sol |
| /test/foundry/periphery/PanopticHelper.t.sol |
| /test/foundry/libraries/harnesses/PanopticMathHarness.sol |
| /test/foundry/libraries/harnesses/MathHarness.sol |
| /test/foundry/libraries/harnesses/FeesCalcHarness.sol |
| /test/foundry/libraries/harnesses/CallbackLibHarness.sol |
| /test/foundry/libraries/SafeTransferLib.t.sol |
| /test/foundry/libraries/PositionAmountsTest.sol |
| /test/foundry/libraries/PanopticMath.t.sol |
| /test/foundry/libraries/Math.t.sol |
| /test/foundry/libraries/FeesCalc.t.sol |
| /test/foundry/libraries/CallbackLib.t.sol |
| /test/foundry/core/SemiFungiblePositionManager.t.sol |
| /test/foundry/core/PanopticPool.t.sol |
| /test/foundry/core/PanopticFactory.t.sol |
| /test/foundry/core/Misc.t.sol |
| /test/foundry/core/CollateralTracker.t.sol |
| /scripts/tokens/ERC20S.sol |
| /periphery/PanopticHelper.sol |

## <span id=t-report>Report</span>

## Overview

The analysis finished with **`0`** errors and **`0`** duplicate files.





### <span style="font-weight: bold" id=t-inline-documentation>Inline Documentation</span>

- **Comment-to-Source Ratio:** On average there are`1.33` code lines per comment (lower=better).
- **ToDo's:** `0`

### <span style="font-weight: bold" id=t-components>Components</span>

| 📝Contracts   | 📚Libraries | 🔍Interfaces | 🎨Abstract |
| ------------- | ----------- | ------------ | ---------- |
| 4 | 11  | 1  | 3 |

### <span style="font-weight: bold" id=t-exposed-functions>Exposed Functions</span>

This section lists functions that are explicitly declared public or payable. Please note that getter methods for public stateVars are not included.

| 🌐Public   | 💰Payable |
| ---------- | --------- |
| 91 | 1  |

| External   | Internal | Private | Pure | View |
| ---------- | -------- | ------- | ---- | ---- |
| 66 | 232  | 3 | 105 | 70 |

### <span style="font-weight: bold" id=t-statevariables>StateVariables</span>

| Total      | 🌐Public  |
| ---------- | --------- |
| 97  | 5 |

### <span style="font-weight: bold" id=t-capabilities>Capabilities</span>

| Solidity Versions observed | 🧪 Experimental Features | 💰 Can Receive Funds | 🖥 Uses Assembly | 💣 Has Destroyable Contracts |
| -------------------------- | ------------------------ | -------------------- | ---------------- | ---------------------------- |
| `^0.8.18`<br/>`^0.8.0` |  | `yes` | `yes` <br/>(31 asm blocks) | **** |

| 📤 Transfers ETH | ⚡ Low-Level Calls | 👥 DelegateCall | 🧮 Uses Hash Functions | 🔖 ECRecover | 🌀 New/Create/Create2 |
| ---------------- | ----------------- | --------------- | ---------------------- | ------------ | --------------------- |
| `yes` | **** | `yes` | `yes` | **** | **** |

| ♻️ TryCatch | Σ Unchecked |
| ---------- | ----------- |
| `yes` | `yes` |

### <span style="font-weight: bold" id=t-package-imports>Dependencies / External Imports</span>

| Dependency / Import Path | Count  |
| ------------------------ | ------ |
| @contracts/CollateralTracker.sol | 4 |
| @contracts/PanopticPool.sol | 1 |
| @contracts/SemiFungiblePositionManager.sol | 3 |
| @libraries/CallbackLib.sol | 2 |
| @libraries/Constants.sol | 7 |
| @libraries/Errors.sol | 10 |
| @libraries/FeesCalc.sol | 2 |
| @libraries/InteractionHelper.sol | 2 |
| @libraries/Math.sol | 7 |
| @libraries/PanopticMath.sol | 6 |
| @libraries/SafeTransferLib.sol | 3 |
| @multicall/Multicall.sol | 4 |
| @openzeppelin/contracts/proxy/Clones.sol | 1 |
| @openzeppelin/contracts/security/ReentrancyGuard.sol | 1 |
| @openzeppelin/contracts/token/ERC1155/ERC1155.sol | 1 |
| @openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol | 2 |
| @openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol | 1 |
| @openzeppelin/contracts/utils/Strings.sol | 1 |
| @tokens/ERC1155Minimal.sol | 1 |
| @tokens/ERC20Minimal.sol | 1 |
| @tokens/interfaces/IERC20Partial.sol | 1 |
| @types/LeftRight.sol | 5 |
| @types/LiquidityChunk.sol | 6 |
| @types/TokenId.sol | 6 |
| univ3-core/interfaces/IUniswapV3Factory.sol | 3 |
| univ3-core/interfaces/IUniswapV3Pool.sol | 5 |


##### Contract Summary

```
Error: extraneous input 'univ3pool' expecting '=>' (103:27)
```
____

