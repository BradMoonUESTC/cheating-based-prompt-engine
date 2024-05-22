// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {EthereumVaultConnector} from "ethereum-vault-connector/EthereumVaultConnector.sol";
import {DeployPermit2} from "./utils/DeployPermit2.sol";

// Contracts
import {GenericFactory} from "../../src/GenericFactory/GenericFactory.sol";
import {EVault} from "../../src/EVault/EVault.sol";
import {ProtocolConfig} from "../../src/ProtocolConfig/ProtocolConfig.sol";
import {IRMTestDefault} from "../mocks/IRMTestDefault.sol";
import {Base} from "../../src/EVault/shared/Base.sol";
import {Dispatch} from "../../src/EVault/Dispatch.sol";
import {SequenceRegistry} from "../../src/SequenceRegistry/SequenceRegistry.sol";

// Modules
import {
    BalanceForwarderExtended,
    BalanceForwarder,
    BorrowingExtended,
    Borrowing,
    GovernanceExtended,
    Governance,
    InitializeExtended,
    Initialize,
    LiquidationExtended,
    Liquidation,
    RiskManagerExtended,
    RiskManager,
    TokenExtended,
    Token,
    VaultExtended,
    Vault
} from "test/invariants/helpers/extended/ModulesExtended.sol";

// Test Contracts
import {ERC20Mock as TestERC20} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockBalanceTracker} from "../mocks/MockBalanceTracker.sol";
import {MockPriceOracle} from "../mocks/MockPriceOracle.sol";
import {Actor} from "./utils/Actor.sol";
import {BaseTest} from "./base/BaseTest.t.sol";
import {EVaultExtended} from "./helpers/extended/EVaultExtended.sol";

/// @title Setup
/// @notice Setup contract for the invariant test Suite, inherited by Tester
contract Setup is BaseTest {
    function _setUp() internal {
        // Deplopy EVC and needed contracts
        _deployProtocolCore();

        // Deploy vaults
        _deployVaults();
    }

    function _deployProtocolCore() internal {
        // Deploy the EVC
        evc = new EthereumVaultConnector();

        // Setup the protocol config
        feeReceiver = _makeAddr("feeReceiver");
        protocolConfig = new ProtocolConfig(address(this), feeReceiver);

        // Deploy the oracle and integrations
        balanceTracker = address(new MockBalanceTracker());
        oracle = new MockPriceOracle();
        sequenceRegistry = address(new SequenceRegistry());

        // Deploy the mock assets
        assetTST = new TestERC20();
        assetTST2 = new TestERC20();
        baseAssets.push(address(assetTST));
        baseAssets.push(address(assetTST2));

        unitOfAccount = address(1);
        permit2 = DeployPermit2.deployPermit2();
    }

    function _deployVaults() internal {
        // Deploy the modules
        Base.Integrations memory integrations =
            Base.Integrations(address(evc), address(protocolConfig), sequenceRegistry, balanceTracker, permit2);

        Dispatch.DeployedModules memory modules = Dispatch.DeployedModules({
            initialize: address(new Initialize(integrations)),
            token: address(new Token(integrations)),
            vault: address(new Vault(integrations)),
            borrowing: address(new Borrowing(integrations)),
            liquidation: address(new Liquidation(integrations)),
            riskManager: address(new RiskManager(integrations)),
            balanceForwarder: address(new BalanceForwarder(integrations)),
            governance: address(new Governance(integrations))
        });

        // Deploy the vault implementation
        address evaultImpl = address(new EVaultExtended(integrations, modules));

        // Deploy the vault factory and set the implementation
        factory = new GenericFactory(address(this));
        factory.setImplementation(evaultImpl);

        // Deploy the vaults
        eTST = EVaultExtended(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        eTST.setInterestRateModel(address(new IRMTestDefault()));
        vaults.push(address(eTST));

        eTST2 = EVaultExtended(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST2), address(oracle), unitOfAccount))
        );
        eTST2.setInterestRateModel(address(new IRMTestDefault()));
        vaults.push(address(eTST2));
    }

    function _setUpActors() internal {
        address[] memory addresses = new address[](3);
        addresses[0] = USER1;
        addresses[1] = USER2;
        addresses[2] = USER3;

        address[] memory tokens = new address[](2);
        tokens[0] = address(assetTST);
        tokens[1] = address(assetTST2);

        for (uint256 i; i < NUMBER_OF_ACTORS; i++) {
            // Deply actor proxies and approve system contracts
            address _actor = _setUpActor(addresses[i], tokens, vaults);

            // Mint initial balances to actors
            for (uint256 j = 0; j < tokens.length; j++) {
                TestERC20 _token = TestERC20(tokens[j]);
                _token.mint(_actor, INITIAL_BALANCE);
            }
            actorAddresses.push(_actor);
        }
    }

    function _setUpActor(address userAddress, address[] memory tokens, address[] memory callers)
        internal
        returns (address actorAddress)
    {
        bool success;
        Actor _actor = new Actor(tokens, callers);
        actors[userAddress] = _actor;
        (success,) = address(_actor).call{value: INITIAL_ETH_BALANCE}("");
        assert(success);
        actorAddress = address(_actor);
    }
}
