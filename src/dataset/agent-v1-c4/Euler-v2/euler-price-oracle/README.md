# Euler Price Oracles

Euler Price Oracles is a library of modular oracle adapters and components that implement `IPriceOracle`, an opinionated quote-based interface.

- To read more about the design and motivation behind `IPriceOracle` and the oracles in this repo, check out the [whitepaper](docs/whitepaper.md).

- To understand how Price Oracles fit into the [Euler Vault Kit](https://github.com/euler-xyz/euler-vault-kit), check out the [price oracles section](https://docs.euler.finance/euler-vault-kit-white-paper/#price-oracles) of the EVK whitepaper.

- To use or develop with Euler Price Oracles, check out the [Usage](#usage) section.

- To find out ways to contribute to Euler Price Oracles, check out the [Contributing](#contributing) section.

Euler Price Oracles has been [audited](audits/) by Spearbit, OpenZeppelin, ChainSecurity, Omniscia and yAudit. Cantina [competition](https://cantina.xyz/competitions/41306bb9-2bb8-4da6-95c3-66b85e11639f) is underway.

## `IPriceOracle`

All contracts in this library implement the `IPriceOracle` interface.
```solidity
/// @return outAmount The amount of `quote` that is equivalent to `inAmount` of `base`.
function getQuote(
    uint256 inAmount, 
    address base, 
    address quote
) external view returns (uint256 outAmount);

/// @return bidOutAmount The amount of `quote` you would get for selling `inAmount` of `base`.
/// @return askOutAmount The amount of `quote` you would spend for buying `inAmount` of `base`.
function getQuotes(
    uint256 inAmount, 
    address base, 
    address quote
) external view returns (uint256 bidOutAmount, uint256 askOutAmount);
```

This interface shapes oracle interactions in an important way: it forces the consumer to think in [amounts rather than prices.](https://hackernoon.com/getting-prices-right)

### Quotes

Euler Price Oracles are unique in that they expose a flexible quoting interface instead of reporting a static price.

> [!NOTE] 
> Imagine a Chainlink price feed which reports the value `1 EUL/ETH`, the *unit price* of `EUL`. Now consider an `IPriceOracle` adapter for the feed. It will fetch the unit price, multiply it by `inAmount`, and return the quantity `inAmount EUL/ETH`. We call this a *quote* as it functionally resembles a swap on a decentralized exchange.

The quoting interface offers several benefits to consumers:
- **More intuitive queries:** Oracles are commonly used in DeFi to determine the value of assets. `getQuote` does exactly that.
- **More expressive interface:** The unit price is a special case of a quote where `inAmount` is one whole unit of `base`.
- **Safe and flexible integrations:** Under `IPriceOracle` adapters are internally responsible for converting decimals. This allows consumers to decouple themselves from a particular provider as they can remain agnostic to its implementation details.

### Bid/Ask Pricing

Euler Price Oracles additionally expose `getQuotes` which returns two prices: the selling price (bid) and the buying price (ask). 

Bid/ask prices are inherently safer to use in lending markets as they can accurately reflect instantaneous price spreads. While few oracles support bid/ask prices currently, we anticipate their wider adoption in DeFi as on-chain liquidity matures. 

Importantly `getQuotes` allows for custom pricing strategies to be built under the `IPriceOracle` interface:
 - Querying two oracles and returning the lower and higher prices.
 - Reporting two prices from a single source e.g. a TWAP and a [median.](https://github.com/euler-xyz/median-oracle)
 - Applying a synthetic spread or a volatility-dependent confidence interval around a mid-price.

## Oracle Adapters

An adapter is a minimal, fully immutable contract that queries an external price feed. It is the atomic building block of the Euler Price Oracles library.

### Design Principles

The `IPriceOracle` interface is permissive in that it does not prescribe a particular way to implement it. However the adapters in this library adhere to a strict set of rules that we believe are necessary to enable safe, open, and self-governed markets to flourish.

#### Immutable

Adapters are fully immutable without governance or upgradeability.

#### Minimally Responsible

An adapter connects to one pricing system and queries a single price feed in that system.

#### Bidirectional

An adapter works in both directions. If it supports quoting `X/Y` it must also support `Y/X`.

#### Observable

An adapter's parameters and acceptance logic are easily observed on-chain.

### Summary of Adapters

| Adapter       | Type      | Subtype | Pairs         | Parameters        |
| ------------- | --------- | ------  | ------------- | -------------------------------------------- |
| Chainlink     | External  | Push    | Vendor feeds  | feed, max staleness                          | 
| Chronicle     | External  | Push    | Vendor feeds  | feed, max staleness                          | 
| Pyth          | External  | Pull    | Vendor feeds  | feed, max staleness, max confidence interval |
| Redstone      | External  | Pull    | Vendor feeds  | feed, max staleness, cache ttl               |
| Lido          | On-chain  | Rate    | wstEth, stEth | -                                            |
| Uniswap V3    | On-chain  | TWAP    | UniV3 pools   | fee, twap window                             |


## Usage

### Install

To install Price Oracles in a [Foundry](https://github.com/foundry-rs/foundry) project:

```sh
forge install euler-xyz/euler-price-oracle
```

### Development

Clone the repo:
```sh
git clone https://github.com/euler-xyz/euler-price-oracle.git && cd euler-price-oracle
```

Install forge dependencies:
```sh
forge install
```

[Optional] Install Node.js dependencies:
```sh
npm install
```

Compile the contracts:
```sh
forge build
```

### Testing

The repo contains 4 types of tests: unit, property, bounds, fork, identified by their filename suffix.

#### Fork Tests

To run fork tests set the `ETHEREUM_RPC_URL` variable in your environment:
```sh
# File: .env
ETHEREUM_RPC_URL=...
```

Alternatively, to exclude fork tests:
```sh
forge test --no-match-contract Fork
```

> [!IMPORTANT]  
> Tests in `RedstoneCoreOracle.fork.t.sol` use the [`ffi`](https://book.getfoundry.sh/cheatcodes/ffi#ffi) cheatcode to invoke a script that retrieves Redstone update data. FFI mode is **not enabled by default** for safety reasons. To run the Redstone Fork tests set `ffi = true` in `foundry.toml`.

## Contributing
Euler Price Oracles is a [free and open-source](LICENSE) public good. We encourage you to engage and contribute. 

Feel free to [open](https://github.com/euler-xyz/euler-price-oracle/issues/new) a GitHub issue discussing your ideas.

> [!TIP]
> Submit testing- and documentation-related PRs to [`development`](https://github.com/euler-xyz/euler-price-oracle/tree/master) and changes under `src/` to [`experiments`](https://github.com/euler-xyz/euler-price-oracle/tree/experiments).

Here are a few ideas how you can improve Euler Price Oracles:

### Research and Development
 - Write an adapter for a new [oracle vendor](https://defillama.com/oracles/chain/Ethereum) or an AMM such as [Curve V2](https://resources.curve.fi/factory-pools/understanding-oracles/#exponential-moving-average) or [Pendle](https://docs.pendle.finance/Developers/Integration/HowToIntegratePtAndLpOracle).
 - `getQuotes` returns bid/ask prices, however we are not aware of any oracle vendors that currently support them. Write an `IPriceOracle` wrapper that applies a price spread around a mid-point price. The spread could be dynamic based on proxy metrics such as liquidity, volume, (implied) volatility, correlation. We are highly interested in research towards this direction.
 - ZK Coprocessors like [Axiom](https://www.axiom.xyz/) and [Lagrange](https://www.lagrange.dev/) allow you to [verifiably compute](https://blog.axiom.xyz/what-is-a-zk-coprocessor/) over historical blockchain state in ZK circuits. This unlocks a new design space for trust-minimized manipulation-resistant oracles. Write a proof-of-concept oracle using a ZK Coprocessor. Some ideas: an [implied volatility oracle](https://lambert-guillaume.medium.com/on-chain-volatility-and-uniswap-v3-d031b98143d1) based on Uniswap V3, a [median filtering oracle](https://github.com/euler-xyz/median-oracle) over an AMM.
 - Write an `IPriceOracle` wrapper that implements a trustless circuit-breaker mechanism that detects failure conditions. Upon detection it could switch to another oracle or redeploy the adapter with different parameters.
 - Write an alternative router to `EulerRouter` that supports more flexible configuration.
 - Research whether a DEX aggregator API can be used as a pull-based price oracle and write a proof-of-concept adapter.
 - Some oracle vendors are compatible with Chainlink's `AggregatorV3Interface` either directly or through a facade contract. Are they safe to use through `ChainlinkOracle` in this library?
 - Write a sanity checking script that verifies an adapter is correctly configured by comparing the quote against a price API.
 - Write a simulation script that generates a line plot comparing a given adapter's prices against a price API historically.

### Security
 - Expand the fork test suite to include more pairs and to historically backtest the adapter.
 - Write fuzz and invariant tests using [echidna](https://github.com/crytic/echidna), [medusa](https://github.com/crytic/medusa), or [foundry](https://book.getfoundry.sh/forge/invariant-testing).
 - Write formal verification tests using [Certora](https://docs.certora.com/en/latest/), [halmos](https://github.com/a16z/halmos), or [kontrol](https://github.com/runtimeverification/kontrol).
 - `EulerRouter` can price ERC4626 shares to assets by calling [`convertToAssets`](https://eips.ethereum.org/EIPS/eip-4626#converttoassets). Which of the [currently live](https://erc4626.info/vaults/) vaults have a manipulation-resistant pricing function?
 - With pull-based oracles users control the price update flow. What is an appropriate value for `maxStaleness` on Ethereum considering network delays and possible censorship? Are there ways `maxStaleness` can be safely reduced?
 - Are these oracles readily usable on the various L2s or are there additional considerations that must be had? 

### Technical Documentation
 - Write an smart contract integration guide for Euler Price Oracles.
 - Write a frontend integration guide for fetching the price of pull-based oracles. 
 - Write or compile risk research for a vendor, detailing how it works, its failure modes and trust assumptions.

## Safety

This software is **experimental** and is provided "as is" and "as available".

**No warranties are provided** and **no liability will be accepted for any loss** incurred through the use of this codebase.

Always include thorough tests when using Euler Price Oracles to ensure it interacts correctly with your code.

Euler Price Oracles is currently undergoing security audits and should not be used in production.

## License

(c) 2024 Euler Labs Ltd.

The Euler Price Oracles code is licensed under the [GPL-2.0-or-later](LICENSE) license.