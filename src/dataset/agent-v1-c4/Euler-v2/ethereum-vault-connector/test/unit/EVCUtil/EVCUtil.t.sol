// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../../src/utils/EVCUtil.sol";
import "../../evc/EthereumVaultConnectorHarness.sol";
import "../../../src/interfaces/IVault.sol";

contract EVCClient is EVCUtil {
    constructor(address _evc) EVCUtil(_evc) {
        // do nothing
    }

    function calledThroughEVCUint(uint256 param) external callThroughEVC returns (uint256) {
        require(msg.sender == address(evc), "Not EVC");
        return param;
    }

    function calledThroughEVCPayableUint(uint256 param) external payable callThroughEVC returns (uint256) {
        require(msg.sender == address(evc), "Not EVC");
        return param;
    }

    function calledThroughEVCBytes(bytes calldata param) external callThroughEVC returns (bytes memory) {
        require(msg.sender == address(evc), "Not EVC");
        return param;
    }

    function calledThroughEVCPayableBytes(bytes calldata param)
        external
        payable
        callThroughEVC
        returns (bytes memory)
    {
        require(msg.sender == address(evc), "Not EVC");
        return param;
    }

    function calledByEVCWithChecksInProgress() external onlyEVCWithChecksInProgress {
        // do nothing
    }

    function msgSender() external view returns (address) {
        return _msgSender();
    }

    function msgSenderForBorrow() external view returns (address) {
        return _msgSenderForBorrow();
    }

    fallback(bytes calldata) external returns (bytes memory) {
        return abi.encode(IVault.checkAccountStatus.selector);
    }
}

contract EVCUtilTest is Test {
    EVCClient internal evcClient;
    EthereumVaultConnectorHarness internal evc;

    function setUp() public {
        evc = new EthereumVaultConnectorHarness();
        evcClient = new EVCClient(address(evc));
    }

    function test_EVC(address _evc) external {
        vm.assume(_evc != address(0));
        EVCClient client = new EVCClient(address(_evc));
        assertEq(client.EVC(), address(_evc));
    }

    function test_EVCUtilConstructor() external {
        vm.expectRevert(EVCUtil.EVC_InvalidAddress.selector);
        new EVCClient(address(0));
    }

    function test_callThroughEVCUint(uint256 input) external {
        {
            // call directly
            uint256 result = evcClient.calledThroughEVCUint(input);
            assertEq(result, input);
        }

        {
            // call through EVC
            bytes memory result = evc.call(
                address(evcClient),
                address(this),
                0,
                abi.encodeWithSelector(evcClient.calledThroughEVCUint.selector, input)
            );
            assertEq(abi.decode(result, (uint256)), input);
        }
    }

    function test_callThroughEVCPayableUint(uint256 input, uint64 value) external {
        vm.deal(address(this), type(uint128).max);

        {
            // call directly
            uint256 balance = address(evcClient).balance;
            uint256 result = evcClient.calledThroughEVCPayableUint{value: value}(input);
            assertEq(result, input);
            assertEq(address(evcClient).balance, balance + value);
        }

        {
            // call through EVC
            uint256 balance = address(evcClient).balance;
            bytes memory result = evc.call{value: value}(
                address(evcClient),
                address(this),
                value,
                abi.encodeWithSelector(evcClient.calledThroughEVCPayableUint.selector, input)
            );
            assertEq(abi.decode(result, (uint256)), input);
            assertEq(address(evcClient).balance, balance + value);
        }
    }

    function test_callThroughEVCBytes(bytes calldata input) external {
        {
            // call directly
            bytes memory result = evcClient.calledThroughEVCBytes(input);
            assertEq(result, input);
        }

        {
            // call through EVC
            bytes memory result = evc.call(
                address(evcClient),
                address(this),
                0,
                abi.encodeWithSelector(evcClient.calledThroughEVCBytes.selector, input)
            );
            assertEq(abi.decode(result, (bytes)), input);
        }
    }

    function test_callThroughEVCPayableBytes(bytes calldata input, uint64 value) external {
        vm.deal(address(this), type(uint128).max);

        {
            // call directly
            uint256 balance = address(evcClient).balance;
            bytes memory result = evcClient.calledThroughEVCPayableBytes{value: value}(input);
            assertEq(result, input);
            assertEq(address(evcClient).balance, balance + value);
        }

        {
            // call through EVC
            uint256 balance = address(evcClient).balance;
            bytes memory result = evc.call{value: value}(
                address(evcClient),
                address(this),
                value,
                abi.encodeWithSelector(evcClient.calledThroughEVCPayableBytes.selector, input)
            );
            assertEq(abi.decode(result, (bytes)), input);
            assertEq(address(evcClient).balance, balance + value);
        }
    }

    function test_calledByEVCWithChecksInProgress(address caller) external {
        vm.assume(caller != address(evc));

        // msg.sender is not EVC, but checks in progress
        evc.setChecksInProgress(true);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(EVCUtil.NotAuthorized.selector));
        evcClient.calledByEVCWithChecksInProgress();

        // msg.sender is EVC, but checks not in progress
        evc.setChecksInProgress(false);
        vm.prank(address(evc));
        vm.expectRevert(abi.encodeWithSelector(EVCUtil.NotAuthorized.selector));
        evcClient.calledByEVCWithChecksInProgress();

        // msg.sender is EVC and checks in progress
        evc.setChecksInProgress(true);
        vm.prank(address(evc));
        evcClient.calledByEVCWithChecksInProgress();
    }

    function test_msgSender(address caller) external {
        vm.assume(caller != address(0) && caller != address(evc));

        // msg.sender is not EVC
        vm.prank(caller);
        assertEq(evcClient.msgSender(), caller);

        // msg.sender is EVC
        vm.prank(caller);
        bytes memory result =
            evc.call(address(evcClient), caller, 0, abi.encodeWithSelector(evcClient.msgSender.selector));
        assertEq(abi.decode(result, (address)), caller);
    }

    function test_msgSenderForBorrow(address caller) external {
        vm.assume(caller != address(0) && caller != address(evc));

        // msg.sender is not EVC and controller not enabled
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(EVCUtil.ControllerDisabled.selector));
        evcClient.msgSenderForBorrow();

        // msg.sender is EVC and controller not enabled
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(EVCUtil.ControllerDisabled.selector));
        evc.call(address(evcClient), caller, 0, abi.encodeWithSelector(evcClient.msgSenderForBorrow.selector));

        // enable controller
        vm.prank(caller);
        evc.enableController(caller, address(evcClient));

        // msg.sender is not EVC and controller enabled
        vm.prank(caller);
        assertEq(evcClient.msgSenderForBorrow(), caller);

        // msg.sender is EVC and controller enabled
        vm.prank(caller);
        bytes memory result =
            evc.call(address(evcClient), caller, 0, abi.encodeWithSelector(evcClient.msgSenderForBorrow.selector));
        assertEq(abi.decode(result, (address)), caller);
    }
}
