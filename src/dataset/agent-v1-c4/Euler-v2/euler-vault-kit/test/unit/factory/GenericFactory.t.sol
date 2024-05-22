// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import {Test, console2, stdError} from "forge-std/Test.sol";
import {GenericFactory} from "../../../src/GenericFactory/GenericFactory.sol";

import {MockEVault} from "../../mocks/MockEVault.sol";
import {TestERC20} from "../../mocks/TestERC20.sol";
import {ReentrancyAttack} from "../../mocks/ReentrancyAttack.sol";

contract FactoryTest is Test {
    GenericFactory public factory;
    address public upgradeAdmin;
    address public otherAccount;

    function setUp() public {
        address admin = vm.addr(1000);

        vm.expectEmit();
        emit GenericFactory.Genesis();

        vm.expectEmit(true, false, false, false);
        emit GenericFactory.SetUpgradeAdmin(admin);

        factory = new GenericFactory(admin);

        // Defaults are all set to admin
        assertEq(factory.upgradeAdmin(), admin);

        // Implementation starts at address(0)
        assertEq(factory.implementation(), address(0));

        upgradeAdmin = vm.addr(1000);
        otherAccount = vm.addr(1001);

        vm.prank(admin);
        factory.setUpgradeAdmin(upgradeAdmin);

        // Newly set values
        assertEq(factory.upgradeAdmin(), upgradeAdmin);
    }

    function test_setImplementationSimple() public {
        vm.prank(upgradeAdmin);
        factory.setImplementation(address(1));
        assertEq(factory.implementation(), address(1));

        vm.prank(upgradeAdmin);
        factory.setImplementation(address(2));
        assertEq(factory.implementation(), address(2));
    }

    function test_activateVaultDefaultImplementation() public {
        // Create and install mock eVault impl
        MockEVault mockEvaultImpl = new MockEVault(address(factory), address(1));
        vm.prank(upgradeAdmin);
        factory.setImplementation(address(mockEvaultImpl));

        // Create token and activate it
        TestERC20 asset = new TestERC20("Test Token", "TST", 17, false);

        // pass address(0) to indicate default desired implementation address
        MockEVault eTST = MockEVault(factory.createProxy(address(0), true, abi.encodePacked(address(asset))));

        // Verify proxying behaves as intended
        assertEq(eTST.implementation(), "TRANSPARENT");

        {
            string memory inputArg = "hello world! 12345678900987654321";

            address randomUser = vm.addr(5000);
            vm.prank(randomUser);
            (string memory outputArg, address theMsgSender, address vaultAsset) = eTST.arbitraryFunction(inputArg);

            assertEq(outputArg, inputArg);
            assertEq(theMsgSender, randomUser);
            assertEq(vaultAsset, address(asset));
        }
    }

    function testFuzz_activateVaultDesiredImplementation(address differentAddress) public {
        // Create and install mock eVault impl
        MockEVault mockEvaultImpl = new MockEVault(address(factory), address(1));
        vm.assume(differentAddress != address(0) && differentAddress != address(mockEvaultImpl));

        vm.prank(upgradeAdmin);
        factory.setImplementation(address(mockEvaultImpl));

        // Create token and activate it
        TestERC20 asset = new TestERC20("Test Token", "TST", 17, false);

        // pass the desired implementation address
        MockEVault eTST =
            MockEVault(factory.createProxy(address(mockEvaultImpl), true, abi.encodePacked(address(asset))));

        // Verify proxying behaves as intended
        assertEq(eTST.implementation(), "TRANSPARENT");

        {
            string memory inputArg = "hello world! 12345678900987654321";

            address randomUser = vm.addr(5000);
            vm.prank(randomUser);
            (string memory outputArg, address theMsgSender, address vaultAsset) = eTST.arbitraryFunction(inputArg);

            assertEq(outputArg, inputArg);
            assertEq(theMsgSender, randomUser);
            assertEq(vaultAsset, address(asset));
        }

        // reverts if the desired implementation doesn't match
        vm.expectRevert(GenericFactory.E_Implementation.selector);
        eTST = MockEVault(factory.createProxy(differentAddress, true, abi.encodePacked(address(asset))));
    }

    function test_getEVaultsListLength() public {
        // Create and install mock eVault impl
        MockEVault mockEvaultImpl = new MockEVault(address(factory), address(1));
        vm.prank(upgradeAdmin);
        factory.setImplementation(address(mockEvaultImpl));

        // Create Tokens and activate Vaults
        uint256 amountEVault = 10;
        for (uint256 i; i < amountEVault; i++) {
            TestERC20 TST = new TestERC20("Test Token", "TST", 18, false);
            MockEVault(factory.createProxy(address(0), true, abi.encodePacked(address(TST))));
        }

        uint256 lenEVaultList = factory.getProxyListLength();

        assertEq(lenEVaultList, amountEVault);
    }

    function test_getEVaultsList() public {
        // Create and install mock eVault impl
        MockEVault mockEvaultImpl = new MockEVault(address(factory), address(1));
        vm.prank(upgradeAdmin);
        factory.setImplementation(address(mockEvaultImpl));

        // Create Tokens and activate Vaults
        uint256 amountEVaults = 100;

        address[] memory eVaultsList = new address[](amountEVaults);

        for (uint256 i; i < amountEVaults; i++) {
            TestERC20 TST = new TestERC20("Test Token", "TST", 18, false);
            MockEVault eVault = MockEVault(factory.createProxy(address(0), true, abi.encodePacked(address(TST))));
            eVaultsList[i] = address(eVault);
        }

        //get eVaults List
        address[] memory listEVaultsTest;
        address[] memory listGenericFactory;

        //test getEVaultsList(0, type(uint).max) - get all eVaults list
        uint256 startIndex = 0;
        uint256 endIndex = type(uint256).max;

        listGenericFactory = factory.getProxyListSlice(startIndex, endIndex);

        listEVaultsTest = eVaultsList;

        assertEq(listGenericFactory, listEVaultsTest);

        //test getEVaultsList(3, 10) - get [3,10) slice
        startIndex = 3;
        endIndex = 10;

        listGenericFactory = factory.getProxyListSlice(startIndex, endIndex);

        listEVaultsTest = new address[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            listEVaultsTest[i - startIndex] = eVaultsList[i];
        }

        assertEq(listGenericFactory, listEVaultsTest);
    }

    function test_getEVaultConfig() public {
        // Create and install mock eVault impl
        MockEVault mockEvaultImpl = new MockEVault(address(factory), address(1));
        vm.prank(upgradeAdmin);
        factory.setImplementation(address(mockEvaultImpl));

        // Create Tokens and activate Vaults
        TestERC20 TST = new TestERC20("Test Token", "TST", 18, false);
        MockEVault eVault = MockEVault(factory.createProxy(address(0), true, abi.encodePacked(address(TST))));

        GenericFactory.ProxyConfig memory config = factory.getProxyConfig(address(eVault));

        assertEq(config.trailingData, abi.encodePacked(address(TST)));

        TST = new TestERC20("Test Token", "TST", 18, false);
        eVault = MockEVault(factory.createProxy(address(0), true, abi.encodePacked(address(TST))));

        config = factory.getProxyConfig(address(eVault));

        assertEq(config.trailingData, abi.encodePacked(address(TST)));
    }

    function test_isProxy(address proxy) public {
        vm.assume(proxy.code.length == 0);

        // Create and install mock eVault impl
        vm.startPrank(upgradeAdmin);
        factory.setImplementation(address(new MockEVault(address(factory), address(1))));

        assertEq(factory.isProxy(proxy), false);

        // Create a Token and activate Vault
        TestERC20 TST = new TestERC20("Test Token", "TST", 18, false);
        proxy = factory.createProxy(address(0), true, abi.encodePacked(address(TST)));

        assertEq(factory.isProxy(proxy), true);
    }

    function test_Event_ProxyCreated() public {
        // Create and install mock eVault impl
        MockEVault mockEvaultImpl = new MockEVault(address(factory), address(1));
        vm.prank(upgradeAdmin);
        factory.setImplementation(address(mockEvaultImpl));

        // Create token and activate it
        TestERC20 asset = new TestERC20("Test Token", "TST", 17, false);

        vm.expectEmit(false, true, true, true);
        emit GenericFactory.ProxyCreated(address(1), true, address(mockEvaultImpl), abi.encodePacked(address(asset)));

        factory.createProxy(address(0), true, abi.encodePacked(address(asset)));
    }

    function test_Event_SetEVaultImplementation() public {
        vm.expectEmit(true, false, false, false);
        emit GenericFactory.SetImplementation(address(1));

        vm.prank(upgradeAdmin);
        factory.setImplementation(address(1));
    }

    function test_Event_SetUpgradeAdmin() public {
        address newUpgradeAdmin = vm.addr(1002);

        vm.expectEmit(true, false, false, false, address(factory));
        emit GenericFactory.SetUpgradeAdmin(newUpgradeAdmin);

        vm.prank(upgradeAdmin);
        factory.setUpgradeAdmin(newUpgradeAdmin);
    }

    function test_RevertIfUnauthorized() public {
        // Nobody addresses are unauthorised

        vm.prank(vm.addr(2000));
        vm.expectRevert(GenericFactory.E_Unauthorized.selector);
        factory.setUpgradeAdmin(address(1));

        // Only upgradeAdmin can upgrade
        vm.prank(otherAccount);
        vm.expectRevert(GenericFactory.E_Unauthorized.selector);
        factory.setImplementation(address(1));
    }

    function test_RevertIfNonReentrancy_ActivateVault() public {
        ReentrancyAttack badVaultImpl = new ReentrancyAttack(address(factory), address(1));
        vm.prank(upgradeAdmin);
        factory.setImplementation(address(badVaultImpl));

        address asset = vm.addr(1);

        vm.expectRevert(GenericFactory.E_Reentrancy.selector);
        factory.createProxy(address(0), false, abi.encodePacked(address(asset)));
    }

    function test_RevertIfImplementation_ActivateVault() public {
        address asset = vm.addr(1);

        vm.expectRevert(GenericFactory.E_Implementation.selector);
        factory.createProxy(address(0), true, abi.encodePacked(address(asset)));
    }

    function test_RevertIfWrongAdminInConstructor() public {
        vm.expectRevert(GenericFactory.E_BadAddress.selector);
        new GenericFactory(address(0));
    }

    function test_RevertIfErrorList_GetEVaultsList() public {
        // Create and install mock eVault impl
        MockEVault mockEvaultImpl = new MockEVault(address(factory), address(1));
        vm.prank(upgradeAdmin);
        factory.setImplementation(address(mockEvaultImpl));

        // Create Tokens and activate Vaults
        uint256 amountEVaults = 100;

        address[] memory eVaultsList = new address[](amountEVaults);

        for (uint256 i; i < amountEVaults; i++) {
            TestERC20 TST = new TestERC20("Test Token", "TST", 18, false);
            MockEVault eVault = MockEVault(factory.createProxy(address(0), true, abi.encodePacked(address(TST))));
            eVaultsList[i] = address(eVault);
        }

        vm.expectRevert(GenericFactory.E_BadQuery.selector);
        factory.getProxyListSlice(0, eVaultsList.length + 1);

        vm.expectRevert(GenericFactory.E_BadQuery.selector);
        factory.getProxyListSlice(50, eVaultsList.length + 1);

        vm.expectRevert(GenericFactory.E_BadQuery.selector);
        factory.getProxyListSlice(1, 0);

        vm.expectRevert(GenericFactory.E_BadQuery.selector);
        factory.getProxyListSlice(1000, 1000);
    }

    function test_WhenNonUpgradeable_CreateProxy() public {
        GenericFactory.ProxyConfig memory config;

        // Create and install mock eVault impl
        MockEVault mockEvaultImpl = new MockEVault(address(factory), address(1));
        vm.prank(upgradeAdmin);
        factory.setImplementation(address(mockEvaultImpl));

        // Create non-upgradeable proxy
        TestERC20 TST = new TestERC20("Test Token", "TST", 18, false);
        MockEVault eVaultNonUpg = MockEVault(factory.createProxy(address(0), false, abi.encodePacked(address(TST))));

        config = factory.getProxyConfig(address(eVaultNonUpg));

        assertEq(config.upgradeable, false);
        assertEq(config.trailingData, abi.encodePacked(address(TST)));

        assertEq(config.implementation, factory.implementation());
        assertEq(eVaultNonUpg.implementation(), "TRANSPARENT");

        // Change eVault impl
        vm.prank(upgradeAdmin);
        factory.setImplementation(address(1));

        config = factory.getProxyConfig(address(eVaultNonUpg));
        assertNotEq(config.implementation, factory.implementation());
        assertEq(eVaultNonUpg.implementation(), "TRANSPARENT");
    }

    function test_payableProxies() public {
        // Create and install mock eVault impl
        MockEVault mockEvaultImpl = new MockEVault(address(factory), address(1));
        vm.prank(upgradeAdmin);
        factory.setImplementation(address(mockEvaultImpl));

        TestERC20 asset = new TestERC20("Test Token", "TST", 17, false);

        // BeaconProxy (upgradeable)
        {
            MockEVault eTST = MockEVault(factory.createProxy(address(0), true, abi.encodePacked(address(asset))));

            assertEq(address(eTST).balance, 0);
            eTST.payMe{value: 12345}();
            assertEq(address(eTST).balance, 12345);
        }

        // MetaProxy (non-upgradeable)
        {
            MockEVault eTST = MockEVault(factory.createProxy(address(0), false, abi.encodePacked(address(asset))));

            assertEq(address(eTST).balance, 0);
            eTST.payMe{value: 12345}();
            assertEq(address(eTST).balance, 12345);
        }
    }
}
