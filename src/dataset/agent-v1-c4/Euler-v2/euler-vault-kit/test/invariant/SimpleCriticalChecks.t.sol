// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";
import {EVaultTestBase} from "../unit/evault/EVaultTestBase.t.sol";
import {IEVault} from "../../src/EVault/IEVault.sol";
import {IRMTestDefault} from "../mocks/IRMTestDefault.sol";
import {MockPriceOracle} from "../mocks/MockPriceOracle.sol";
import "forge-std/console.sol";

interface IGovernanceOverride {
    function resetInitOperationFlag() external;
}

// Entry Point contract for the fuzzer. Bounds the inputs and prepares the environment for the tests.
contract EntryPoint is Test {
    error EVault_Panic();

    IEVC immutable evc;
    address immutable governor;
    IEVault[] eTST;
    address[] account;
    string[] errors;

    uint256 snapshot;
    IEVault selectedVault;

    constructor(IEVault[] memory eTST_, address[] memory account_) {
        evc = IEVC(eTST_[0].EVC());
        governor = eTST_[0].governorAdmin();

        eTST = new IEVault[](eTST_.length);
        eTST = eTST_;

        account = new address[](account_.length);
        account = account_;

        snapshot = vm.snapshot();
    }

    function getErrors() public view returns (string[] memory) {
        return errors;
    }

    // this modifier disables prank mode after the call and checks if the accounts are healthy
    modifier afterCall() {
        _;
        vm.stopPrank();

        if (bytes4(msg.data) != EntryPoint(address(this)).liquidate.selector) {
            for (uint256 i = 0; i < account.length; i++) {
                address[] memory controllers = evc.getControllers(account[i]);

                if (controllers.length == 0) break;

                (uint256 collateralValue, uint256 liabilityValue) =
                    IEVault(controllers[0]).accountLiquidity(account[i], false);

                if (liabilityValue != 0 && liabilityValue >= collateralValue) {
                    errors.push("EVault Panic on afterCall");
                }
            }
        }

        // revert the snapshot only if there are no errors
        if (snapshot != 0 && errors.length == 0) {
            vm.revertTo(snapshot);
            snapshot = 0;
        }
    }

    // this function prepares the environment:
    // 1. sets the special bit in the hooked ops bitfield so that it's possible whether initOperation was called
    // 2. tries to disable the controller of the selected vault and checks if the debt is zero
    // 3. enables random vault as a controller
    function setupEnvironment(uint256 seed) private {
        delete errors;

        vm.stopPrank();
        vm.startPrank(governor);
        selectedVault = eTST[seed % eTST.length];
        // this will fail if there's no overrides on
        try IGovernanceOverride(address(selectedVault)).resetInitOperationFlag() {} catch {}
        vm.stopPrank();

        vm.startPrank(msg.sender);

        try selectedVault.disableController() {
            if (selectedVault.debtOf(msg.sender) != 0) errors.push("EVault Panic on disableController");
        } catch {}

        try evc.enableController(msg.sender, address(eTST[uint256(keccak256(abi.encode(seed))) % eTST.length])) {}
            catch {}
    }

    function boundAmount(uint256 amount) private pure returns (uint256) {
        return bound(amount, 1, type(uint64).max);
    }

    function boundAddress(address addr) private view returns (address) {
        return account[uint160(addr) % account.length];
    }

    function transfer(uint256 seed, address to, uint256 amount) public afterCall {
        setupEnvironment(seed);

        to = boundAddress(to);
        amount = boundAmount(amount);

        try selectedVault.transfer(to, amount) {
            assertTrue(true);
        } catch (bytes memory reason) {
            if (bytes4(reason) == EVault_Panic.selector) errors.push("EVault Panic on transfer");
        }
    }

    function transferFrom(uint256 seed, address from, address to, uint256 amount) public afterCall {
        setupEnvironment(seed);

        from = boundAddress(from);
        to = boundAddress(to);
        amount = boundAmount(amount);

        try selectedVault.transferFrom(from, to, amount) {
            assertTrue(true);
        } catch (bytes memory reason) {
            if (bytes4(reason) == EVault_Panic.selector) errors.push("EVault Panic on transferFrom");
        }
    }

    function approve(uint256 seed, address spender, uint256 amount) public afterCall {
        setupEnvironment(seed);

        spender = boundAddress(spender);

        try selectedVault.approve(spender, amount) {
            assertTrue(true);
        } catch (bytes memory reason) {
            if (bytes4(reason) == EVault_Panic.selector) errors.push("EVault Panic on approve");
        }
    }

    function transferFromMax(uint256 seed, address from, address to) public afterCall {
        setupEnvironment(seed);

        from = boundAddress(from);
        to = boundAddress(to);

        try selectedVault.transferFromMax(from, to) {
            assertTrue(true);
        } catch (bytes memory reason) {
            if (bytes4(reason) == EVault_Panic.selector) errors.push("EVault Panic on transferFromMax");
        }
    }

    function deposit(uint256 seed, uint256 amount, address receiver) public afterCall {
        setupEnvironment(seed);

        amount = boundAmount(amount);
        receiver = boundAddress(receiver);

        try selectedVault.deposit(amount, receiver) {
            assertTrue(true);
        } catch (bytes memory reason) {
            if (bytes4(reason) == EVault_Panic.selector) errors.push("EVault Panic on deposit");
        }
    }

    function mint(uint256 seed, uint256 amount, address receiver) public afterCall {
        setupEnvironment(seed);

        amount = boundAmount(amount);
        receiver = boundAddress(receiver);

        try selectedVault.mint(amount, receiver) {
            assertTrue(true);
        } catch (bytes memory reason) {
            if (bytes4(reason) == EVault_Panic.selector) errors.push("EVault Panic on mint");
        }
    }

    function withdraw(uint256 seed, uint256 amount, address receiver, address owner) public afterCall {
        setupEnvironment(seed);

        amount = boundAmount(amount);
        receiver = boundAddress(receiver);
        owner = boundAddress(owner);

        try selectedVault.withdraw(amount, receiver, owner) {
            assertTrue(true);
        } catch (bytes memory reason) {
            if (bytes4(reason) == EVault_Panic.selector) errors.push("EVault Panic on withdraw");
        }
    }

    function redeem(uint256 seed, uint256 amount, address receiver, address owner) public afterCall {
        setupEnvironment(seed);

        receiver = boundAddress(receiver);
        owner = boundAddress(owner);

        try selectedVault.redeem(amount, receiver, owner) {
            assertTrue(true);
        } catch (bytes memory reason) {
            if (bytes4(reason) == EVault_Panic.selector) errors.push("EVault Panic on redeem");
        }
    }

    function skim(uint256 seed, uint256 amount, address receiver) public afterCall {
        setupEnvironment(seed);

        receiver = boundAddress(receiver);

        try selectedVault.skim(amount, receiver) {
            assertTrue(true);
        } catch (bytes memory reason) {
            if (bytes4(reason) == EVault_Panic.selector) errors.push("EVault Panic on skim");
        }
    }

    function borrow(uint256 seed, uint256 amount, address receiver) public afterCall {
        setupEnvironment(seed);

        amount = boundAmount(amount);
        receiver = boundAddress(receiver);

        try selectedVault.borrow(amount, receiver) {
            assertTrue(true);
        } catch (bytes memory reason) {
            if (bytes4(reason) == EVault_Panic.selector) errors.push("EVault Panic on borrow");
        }
    }

    function repay(uint256 seed, uint256 amount, address receiver) public afterCall {
        setupEnvironment(seed);

        receiver = boundAddress(receiver);

        try selectedVault.repay(amount, receiver) {
            assertTrue(true);
        } catch (bytes memory reason) {
            if (bytes4(reason) == EVault_Panic.selector) errors.push("EVault Panic on repay");
        }
    }

    function repayWithShares(uint256 seed, uint256 amount, address receiver) public afterCall {
        setupEnvironment(seed);

        receiver = boundAddress(receiver);

        try selectedVault.repayWithShares(amount, receiver) {
            assertTrue(true);
        } catch (bytes memory reason) {
            if (bytes4(reason) == EVault_Panic.selector) errors.push("EVault Panic on repayWithShares");
        }
    }

    function pullDebt(uint256 seed, uint256 amount, address from) public afterCall {
        setupEnvironment(seed);

        from = boundAddress(from);

        try selectedVault.pullDebt(amount, from) {
            assertTrue(true);
        } catch (bytes memory reason) {
            if (bytes4(reason) == EVault_Panic.selector) errors.push("EVault Panic on pullDebt");
        }
    }

    function liquidate(uint256 seed, address violator, address collateral, uint256 repayAssets, uint256 minYieldBalance)
        public
        afterCall
    {
        setupEnvironment(seed);

        violator = boundAddress(violator);
        collateral = selectedVault.LTVList()[0];
        repayAssets = boundAmount(repayAssets);
        minYieldBalance = 0;

        address oracle = selectedVault.oracle();

        // take a snapshot to revert the price change and liquidation
        snapshot = vm.snapshot();

        // set lower price for collateral so that maybe a liquidation opportunity occurs
        MockPriceOracle(oracle).setPrice(collateral, selectedVault.unitOfAccount(), 1e17);

        try selectedVault.liquidate(violator, collateral, repayAssets, minYieldBalance) {
            assertTrue(true);
        } catch (bytes memory reason) {
            if (bytes4(reason) == EVault_Panic.selector) errors.push("EVault Panic on liquidate");
        }
    }

    function convertFees() public afterCall {
        setupEnvironment(0);

        try selectedVault.convertFees() {
            assertTrue(true);
        } catch (bytes memory reason) {
            if (bytes4(reason) == EVault_Panic.selector) errors.push("EVault Panic on convertFees");
        }
    }

    function touch() public afterCall {
        setupEnvironment(0);

        try selectedVault.touch() {
            assertTrue(true);
        } catch (bytes memory reason) {
            if (bytes4(reason) == EVault_Panic.selector) errors.push("EVault Panic on touch");
        }
    }
}

contract EVault_SimpleCriticalChecks is EVaultTestBase {
    EntryPoint entryPoint;
    address[] account_;

    function setUp() public override {
        // Setup

        super.setUp();

        oracle.setPrice(address(assetTST), unitOfAccount, 1e18);
        oracle.setPrice(address(assetTST2), unitOfAccount, 1e18);
        oracle.setPrice(address(eTST), unitOfAccount, 1e18);
        oracle.setPrice(address(eTST2), unitOfAccount, 1e18);

        eTST.setLTV(address(eTST2), 0.9e4, 0.9e4, 0);
        eTST2.setLTV(address(eTST), 0.5e4, 0.5e4, 0);

        // accounts

        account_ = new address[](3);
        account_[0] = makeAddr("account0");
        account_[1] = makeAddr("account1");
        account_[2] = makeAddr("account2");

        for (uint256 i = 0; i < account_.length; ++i) {
            assetTST.mint(account_[i], type(uint256).max);
            assetTST2.mint(account_[i], type(uint256).max);

            vm.startPrank(account_[i]);
            assetTST.approve(address(eTST), type(uint256).max);
            assetTST2.approve(address(eTST2), type(uint256).max);
            evc.enableCollateral(account_[i], address(eTST));
            evc.enableCollateral(account_[i], address(eTST2));
            vm.stopPrank();

            targetSender(account_[i]);
        }

        // Fuzzer setup

        IEVault[] memory eTST_ = new IEVault[](2);
        eTST_[0] = eTST;
        eTST_[1] = eTST2;

        entryPoint = new EntryPoint(eTST_, account_);
        targetContract(address(entryPoint));
    }

    function invariant_SimpleCriticalChecks() public view {
        string[] memory errors = entryPoint.getErrors();

        if (errors.length > 0) {
            for (uint256 i = 0; i < errors.length; i++) {
                console.log(errors[i]);
            }
            assertTrue(false);
        }
    }
}
