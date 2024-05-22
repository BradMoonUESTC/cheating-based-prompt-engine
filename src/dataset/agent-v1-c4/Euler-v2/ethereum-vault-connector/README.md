# Ethereum Vault Connector

The Ethereum Vault Connector (EVC) is a foundational layer designed to facilitate the core functionality required for a lending market. It serves as a base building block for various protocols, providing a robust and flexible framework for developers to build upon. The EVC primarily mediates between vaults, contracts that implement the [ERC-4626](https://ethereum.org/en/developers/docs/standards/tokens/erc-4626/) interface and contain additional logic for interfacing with other vaults. The EVC not only provides a common base ecosystem but also reduces complexity in the core lending/borrowing contracts, allowing them to focus on their differentiating factors.

For more information, visit the [EVC website](https://evc.wtf/) or refer to the [whitepaper](https://github.com/euler-xyz/ethereum-vault-connector/tree/master/docs/whitepaper.md).

---

## Contracts

```
.
├── interfaces
│   ├── IERC1271.sol
│   ├── IEthereumVaultConnector.sol
│   └── IVault.sol
├── utils
│   └── EVCUtil.sol
├── Errors.sol
├── EthereumVaultConnector.sol
├── Events.sol
├── ExecutionContext.sol
├── Set.sol
└── TransientStorage.sol
```

## Install

To install Ethereum Vault Connector in a [Foundry](https://github.com/foundry-rs/foundry) project:

```sh
forge install euler-xyz/ethereum-vault-connector
```

## Usage

The Ethereum Vault Connector comes with a comprehensive set of tests written in Solidity, which can be executed using Foundry.

For a detailed understanding of the Ethereum Vault Connector and considerations for its integration, please refer to the [EVC website](https://evc.wtf/), the [whitepaper](https://github.com/euler-xyz/ethereum-vault-connector/tree/master/docs/whitepaper.md). You can find examples of vaults utilizing the Ethereum Vault Connector in the [EVC Playground](https://github.com/euler-xyz/evc-playground/tree/master/src) repository. However, these example vaults are not meant for production use as they have not been audited and are intended solely for testing and experimentation purposes.

To install Foundry:

```sh
curl -L https://foundry.paradigm.xyz | bash
```

This will download foundryup. To start Foundry, run:

```sh
foundryup
```

To clone the repo:

```sh
git clone https://github.com/euler-xyz/ethereum-vault-connector.git && cd ethereum-vault-connector
```

## Testing

### in `default` mode

To run the tests in a `default` mode:

```sh
forge test
```

### with `scribble` annotations

To run the tests using `scribble` annotations first install [scribble](https://docs.scribble.codes/):

```sh
npm install -g eth-scribble
```

To instrument the contracts and run the tests:

```sh
scribble test/evc/EthereumVaultConnectorScribble.sol --output-mode files --arm && forge test
```

To remove instrumentation:

```sh
scribble test/evc/EthereumVaultConnectorScribble.sol --disarm
```

### in `coverage` mode

```sh
forge coverage
```

## Safety

This software is **experimental** and is provided "as is" and "as available".

**No warranties are provided** and **no liability will be accepted for any loss** incurred through the use of this codebase.

Always include thorough tests when using the Ethereum Vault Connector to ensure it interacts correctly with your code.

The Ethereum Vault Connector is currently undergoing security audits and should not be used in production.

## Known limitations

Refer to the [whitepaper](https://github.com/euler-xyz/ethereum-vault-connector/tree/master/docs/whitepaper.md#security-considerations) for a list of known limitations and security considerations.

## Contributing

The code is currently in an experimental phase. Feedback or ideas for improving the Ethereum Vault Connector are appreciated. Contributions are welcome from anyone interested in conducting security research, writing more tests including formal verification, improving readability and documentation, optimizing, simplifying, or developing integrations.

## License

Licensed under the [GPL-2.0-or-later](https://github.com/euler-xyz/ethereum-vault-connector/tree/master/LICENSE) license.
