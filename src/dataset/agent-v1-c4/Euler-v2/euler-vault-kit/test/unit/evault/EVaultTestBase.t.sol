// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import {Test, console2, stdError} from "forge-std/Test.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";

import {GenericFactory} from "../../../src/GenericFactory/GenericFactory.sol";

import {EVault} from "../../../src/EVault/EVault.sol";
import {ProtocolConfig} from "../../../src/ProtocolConfig/ProtocolConfig.sol";

import {Dispatch} from "../../../src/EVault/Dispatch.sol";

import {Initialize} from "../../../src/EVault/modules/Initialize.sol";
import {Token} from "../../../src/EVault/modules/Token.sol";
import {Vault} from "../../../src/EVault/modules/Vault.sol";
import {Borrowing} from "../../../src/EVault/modules/Borrowing.sol";
import {Liquidation} from "../../../src/EVault/modules/Liquidation.sol";
import {BalanceForwarder} from "../../../src/EVault/modules/BalanceForwarder.sol";
import {Governance} from "../../../src/EVault/modules/Governance.sol";
import {RiskManager} from "../../../src/EVault/modules/RiskManager.sol";

import {IEVault, IERC20} from "../../../src/EVault/IEVault.sol";
import {TypesLib} from "../../../src/EVault/shared/types/Types.sol";
import {Base} from "../../../src/EVault/shared/Base.sol";

import {EthereumVaultConnector} from "ethereum-vault-connector/EthereumVaultConnector.sol";

import {TestERC20} from "../../mocks/TestERC20.sol";
import {MockBalanceTracker} from "../../mocks/MockBalanceTracker.sol";
import {MockPriceOracle} from "../../mocks/MockPriceOracle.sol";
import {IRMTestDefault} from "../../mocks/IRMTestDefault.sol";
import {IHookTarget} from "../../../src/interfaces/IHookTarget.sol";
import {SequenceRegistry} from "../../../src/SequenceRegistry/SequenceRegistry.sol";

import {AssertionsCustomTypes} from "../../helpers/AssertionsCustomTypes.sol";
import "./InvariantOverrides.sol";

import "../../../src/EVault/shared/Constants.sol";

contract EVaultTestBase is AssertionsCustomTypes, Test, DeployPermit2 {
    EthereumVaultConnector public evc;
    address admin;
    address feeReceiver;
    address protocolFeeReceiver;
    ProtocolConfig protocolConfig;
    address balanceTracker;
    MockPriceOracle oracle;
    address unitOfAccount;
    address permit2;
    address sequenceRegistry;
    GenericFactory public factory;

    Base.Integrations integrations;
    Dispatch.DeployedModules modules;

    TestERC20 assetTST;
    TestERC20 assetTST2;

    IEVault public eTST;
    IEVault public eTST2;

    address initializeModule;
    address tokenModule;
    address vaultModule;
    address borrowingModule;
    address liquidationModule;
    address riskManagerModule;
    address balanceForwarderModule;
    address governanceModule;

    function setUp() public virtual {
        bool deployOverrides = vm.envOr("DEPLOY_OVERRIDES", false);
        admin = vm.addr(1000);
        feeReceiver = makeAddr("feeReceiver");
        protocolFeeReceiver = makeAddr("protocolFeeReceiver");
        factory = new GenericFactory(admin);

        evc = new EthereumVaultConnector();
        protocolConfig = new ProtocolConfig(admin, protocolFeeReceiver);
        balanceTracker = address(new MockBalanceTracker());
        oracle = new MockPriceOracle();
        unitOfAccount = address(1);
        permit2 = deployPermit2();
        sequenceRegistry = address(new SequenceRegistry());
        integrations =
            Base.Integrations(address(evc), address(protocolConfig), sequenceRegistry, balanceTracker, permit2);

        if (deployOverrides) {
            initializeModule = address(new InitializeOverride(integrations));
            tokenModule = address(new TokenOverride(integrations));
            vaultModule = address(new VaultOverride(integrations));
            borrowingModule = address(new BorrowingOverride(integrations));
            liquidationModule = address(new LiquidationOverride(integrations));
            riskManagerModule = address(new RiskManagerOverride(integrations));
            balanceForwarderModule = address(new BalanceForwarderOverride(integrations));
            governanceModule = address(new GovernanceOverride(integrations));
        } else {
            initializeModule = address(new Initialize(integrations));
            tokenModule = address(new Token(integrations));
            vaultModule = address(new Vault(integrations));
            borrowingModule = address(new Borrowing(integrations));
            liquidationModule = address(new Liquidation(integrations));
            riskManagerModule = address(new RiskManager(integrations));
            balanceForwarderModule = address(new BalanceForwarder(integrations));
            governanceModule = address(new Governance(integrations));
        }

        modules = Dispatch.DeployedModules({
            initialize: initializeModule,
            token: tokenModule,
            vault: vaultModule,
            borrowing: borrowingModule,
            liquidation: liquidationModule,
            riskManager: riskManagerModule,
            balanceForwarder: balanceForwarderModule,
            governance: governanceModule
        });

        address evaultImpl;
        if (deployOverrides) {
            evaultImpl = address(new EVaultOverride(integrations, modules));
        } else {
            evaultImpl = address(new EVault(integrations, modules));
        }

        vm.prank(admin);
        factory.setImplementation(evaultImpl);

        assetTST = new TestERC20("Test Token", "TST", 18, false);
        assetTST2 = new TestERC20("Test Token 2", "TST2", 18, false);

        eTST = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        eTST.setInterestRateModel(address(new IRMTestDefault()));
        eTST.setMaxLiquidationDiscount(0.2e4);
        eTST.setFeeReceiver(feeReceiver);

        eTST2 = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST2), address(oracle), unitOfAccount))
        );
        eTST2.setInterestRateModel(address(new IRMTestDefault()));
        eTST2.setMaxLiquidationDiscount(0.2e4);
        eTST2.setFeeReceiver(feeReceiver);
    }

    address internal SYNTH_VAULT_HOOK_TARGET = address(new MockHook());
    uint32 internal constant SYNTH_VAULT_HOOKED_OPS = OP_DEPOSIT | OP_MINT | OP_REDEEM | OP_SKIM | OP_REPAY_WITH_SHARES;

    function createSynthEVault(address asset) internal returns (IEVault) {
        IEVault v = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(asset), address(oracle), unitOfAccount))
        );
        v.setInterestRateModel(address(new IRMTestDefault()));

        v.setInterestFee(1e4);

        v.setHookConfig(SYNTH_VAULT_HOOK_TARGET, SYNTH_VAULT_HOOKED_OPS);

        return v;
    }

    function getSubAccount(address primary, uint8 subAccountId) internal pure returns (address) {
        require(subAccountId <= 256, "invalid subAccountId");
        return address(uint160(uint160(primary) ^ subAccountId));
    }
}

contract MockHook is IHookTarget {
    error E_OnlyAssetCanDeposit();
    error E_OperationDisabled();

    function isHookTarget() external pure override returns (bytes4) {
        return this.isHookTarget.selector;
    }

    // deposit is only allowed for the asset
    function deposit(uint256, address) external view {
        address asset = IEVault(msg.sender).asset();

        // these calls are just to test if there's no RO-reentrancy for the hook target
        IEVault(msg.sender).totalBorrows();
        IEVault(msg.sender).balanceOf(address(this));

        if (asset != caller()) revert E_OnlyAssetCanDeposit();
    }

    // all the other hooked ops are disabled
    fallback() external {
        revert E_OperationDisabled();
    }

    function caller() internal pure returns (address _caller) {
        assembly {
            _caller := shr(96, calldataload(sub(calldatasize(), 20)))
        }
    }
}
