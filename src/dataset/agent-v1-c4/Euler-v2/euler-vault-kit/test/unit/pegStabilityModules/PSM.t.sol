// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {PegStabilityModule, EVCUtil} from "../../../src/Synths/PegStabilityModule.sol";
import {ESynth, IEVC} from "../../../src/Synths/ESynth.sol";
import {TestERC20} from "../../mocks/TestERC20.sol";
import {EthereumVaultConnector} from "ethereum-vault-connector/EthereumVaultConnector.sol";
import {EVCUtil} from "ethereum-vault-connector/utils/EVCUtil.sol";

contract PSMTest is Test {
    uint256 public TO_UNDERLYING_FEE = 30;
    uint256 public TO_SYNTH_FEE = 30;
    uint256 public BPS_SCALE = 10000;
    uint256 public CONVERSION_PRICE = 1e18;
    uint256 public PRICE_SCALE = 1e18;

    ESynth public synth;
    TestERC20 public underlying;

    PegStabilityModule public psm;

    IEVC public evc;

    address public owner = makeAddr("owner");
    address public wallet1 = makeAddr("wallet1");
    address public wallet2 = makeAddr("wallet2");

    function setUp() public {
        // Deploy EVC
        evc = new EthereumVaultConnector();

        // Deploy underlying
        underlying = new TestERC20("TestUnderlying", "TUNDERLYING", 18, false);

        // Deploy synth
        vm.prank(owner);
        synth = new ESynth(evc, "TestSynth", "TSYNTH");

        // Deploy PSM
        vm.prank(owner);
        psm = new PegStabilityModule(
            address(evc), address(synth), address(underlying), TO_UNDERLYING_FEE, TO_SYNTH_FEE, CONVERSION_PRICE
        );

        // Give PSM and wallets some underlying
        underlying.mint(address(psm), 100e18);
        underlying.mint(wallet1, 100e18);
        underlying.mint(wallet2, 100e18);

        // Approve PSM to spend underlying
        vm.prank(wallet1);
        underlying.approve(address(psm), 100e18);
        vm.prank(wallet2);
        underlying.approve(address(psm), 100e18);

        // Set PSM as minter
        vm.prank(owner);
        synth.setCapacity(address(psm), 100e18);

        // Mint some synth to wallets
        vm.startPrank(owner);
        synth.setCapacity(owner, 200e18);
        synth.mint(wallet1, 100e18);
        synth.mint(wallet2, 100e18);
        vm.stopPrank();

        // Set approvals for PSM
        vm.prank(wallet1);
        synth.approve(address(psm), 100e18);
        vm.prank(wallet2);
        synth.approve(address(psm), 100e18);
    }

    function testConstructor() public view {
        assertEq(address(psm.synth()), address(synth));
        assertEq(psm.TO_UNDERLYING_FEE(), TO_UNDERLYING_FEE);
        assertEq(psm.TO_SYNTH_FEE(), TO_SYNTH_FEE);
    }

    function testConstructorToUnderlyingFeeExceedsBPS() public {
        vm.expectRevert(PegStabilityModule.E_FeeExceedsBPS.selector);
        new PegStabilityModule(
            address(evc), address(synth), address(underlying), BPS_SCALE + 1, TO_SYNTH_FEE, CONVERSION_PRICE
        );
    }

    function testConstructorToSynthFeeExceedsBPS() public {
        vm.expectRevert(PegStabilityModule.E_FeeExceedsBPS.selector);
        new PegStabilityModule(
            address(evc), address(synth), address(underlying), TO_UNDERLYING_FEE, BPS_SCALE + 1, CONVERSION_PRICE
        );
    }

    function testConstructorEVCZeroAddress() public {
        vm.expectRevert(bytes4(keccak256("EVC_InvalidAddress()")));
        new PegStabilityModule(
            address(0), address(synth), address(underlying), TO_UNDERLYING_FEE, TO_SYNTH_FEE, CONVERSION_PRICE
        );
    }

    function testConstructorSynthZeroAddress() public {
        vm.expectRevert(PegStabilityModule.E_ZeroAddress.selector);
        new PegStabilityModule(
            address(evc), address(0), address(underlying), TO_UNDERLYING_FEE, TO_SYNTH_FEE, CONVERSION_PRICE
        );
    }

    function testConstructorUnderlyingZeroAddress() public {
        vm.expectRevert(PegStabilityModule.E_ZeroAddress.selector);
        new PegStabilityModule(
            address(evc), address(synth), address(0), TO_UNDERLYING_FEE, TO_SYNTH_FEE, CONVERSION_PRICE
        );
    }

    function testSwapToUnderlyingGivenIn() public {
        uint256 amountIn = 10e18;
        uint256 expectedAmountOut = amountIn * (BPS_SCALE - TO_UNDERLYING_FEE) / BPS_SCALE;

        uint256 swapperSynthBalanceBefore = synth.balanceOf(wallet1);
        uint256 receiverBalanceBefore = underlying.balanceOf(wallet2);
        uint256 psmUnderlyingBalanceBefore = underlying.balanceOf(address(psm));

        vm.prank(wallet1);
        psm.swapToUnderlyingGivenIn(amountIn, wallet2);

        uint256 swapperSynthBalanceAfter = synth.balanceOf(wallet1);
        uint256 receiverBalanceAfter = underlying.balanceOf(wallet2);
        uint256 psmUnderlyingBalanceAfter = underlying.balanceOf(address(psm));

        assertEq(swapperSynthBalanceAfter, swapperSynthBalanceBefore - amountIn);
        assertEq(receiverBalanceAfter, receiverBalanceBefore + expectedAmountOut);
        assertEq(psmUnderlyingBalanceAfter, psmUnderlyingBalanceBefore - expectedAmountOut);
    }

    function testSwapToUnderlyingGivenOut() public {
        uint256 amountOut = 10e18;
        uint256 expectedAmountIn = amountOut * BPS_SCALE / (BPS_SCALE - TO_UNDERLYING_FEE);

        uint256 swapperSynthBalanceBefore = synth.balanceOf(wallet1);
        uint256 receiverBalanceBefore = underlying.balanceOf(wallet2);
        uint256 psmUnderlyingBalanceBefore = underlying.balanceOf(address(psm));

        vm.prank(wallet1);
        psm.swapToUnderlyingGivenOut(amountOut, wallet2);

        uint256 swapperSynthBalanceAfter = synth.balanceOf(wallet1);
        uint256 receiverBalanceAfter = underlying.balanceOf(wallet2);
        uint256 psmUnderlyingBalanceAfter = underlying.balanceOf(address(psm));

        assertEq(swapperSynthBalanceAfter, swapperSynthBalanceBefore - expectedAmountIn);
        assertEq(receiverBalanceAfter, receiverBalanceBefore + amountOut);
        assertEq(psmUnderlyingBalanceAfter, psmUnderlyingBalanceBefore - amountOut);
    }

    function testSwapToSynthGivenIn() public {
        uint256 amountIn = 10e18;
        uint256 expectedAmountOut = amountIn * (BPS_SCALE - TO_SYNTH_FEE) / BPS_SCALE;

        uint256 swapperUnderlyingBalanceBefore = underlying.balanceOf(wallet1);
        uint256 receiverSynthBalanceBefore = synth.balanceOf(wallet2);
        uint256 psmUnderlyingBalanceBefore = underlying.balanceOf(address(psm));

        vm.prank(wallet1);
        psm.swapToSynthGivenIn(amountIn, wallet2);

        uint256 swapperUnderlyingBalanceAfter = underlying.balanceOf(wallet1);
        uint256 receiverSynthBalanceAfter = synth.balanceOf(wallet2);
        uint256 psmUnderlyingBalanceAfter = underlying.balanceOf(address(psm));

        assertEq(swapperUnderlyingBalanceAfter, swapperUnderlyingBalanceBefore - amountIn);
        assertEq(receiverSynthBalanceAfter, receiverSynthBalanceBefore + expectedAmountOut);
        assertEq(psmUnderlyingBalanceAfter, psmUnderlyingBalanceBefore + amountIn);
    }

    function testSwapToSynthGivenOut() public {
        uint256 amountOut = 10e18;
        uint256 expectedAmountIn = amountOut * BPS_SCALE / (BPS_SCALE - TO_SYNTH_FEE);

        uint256 swapperUnderlyingBalanceBefore = underlying.balanceOf(wallet1);
        uint256 receiverSynthBalanceBefore = synth.balanceOf(wallet2);
        uint256 psmUnderlyingBalanceBefore = underlying.balanceOf(address(psm));

        vm.prank(wallet1);
        psm.swapToSynthGivenOut(amountOut, wallet2);

        uint256 swapperUnderlyingBalanceAfter = underlying.balanceOf(wallet1);
        uint256 receiverSynthBalanceAfter = synth.balanceOf(wallet2);
        uint256 psmUnderlyingBalanceAfter = underlying.balanceOf(address(psm));

        assertEq(swapperUnderlyingBalanceAfter, swapperUnderlyingBalanceBefore - expectedAmountIn);
        assertEq(receiverSynthBalanceAfter, receiverSynthBalanceBefore + amountOut);
        assertEq(psmUnderlyingBalanceAfter, psmUnderlyingBalanceBefore + expectedAmountIn);
    }

    // Test quotes
    function testQuoteToUnderlyingGivenIn() public view {
        uint256 amountIn = 10e18;
        uint256 expectedAmountOut = amountIn * (BPS_SCALE - TO_UNDERLYING_FEE) / BPS_SCALE;

        uint256 amountOut = psm.quoteToUnderlyingGivenIn(amountIn);

        assertEq(amountOut, expectedAmountOut);
    }

    function testQuoteToUnderlyingGivenOut() public view {
        uint256 amountOut = 10e18;
        uint256 expectedAmountIn = amountOut * BPS_SCALE / (BPS_SCALE - TO_UNDERLYING_FEE);

        uint256 amountIn = psm.quoteToUnderlyingGivenOut(amountOut);

        assertEq(amountIn, expectedAmountIn);
    }

    function testQuoteToSynthGivenIn() public view {
        uint256 amountIn = 10e18;
        uint256 expectedAmountOut = amountIn * (BPS_SCALE - TO_SYNTH_FEE) / BPS_SCALE;

        uint256 amountOut = psm.quoteToSynthGivenIn(amountIn);

        assertEq(amountOut, expectedAmountOut);
    }

    function testQuoteToSynthGivenOut() public view {
        uint256 amountOut = 10e18;
        uint256 expectedAmountIn = amountOut * BPS_SCALE / (BPS_SCALE - TO_SYNTH_FEE);

        uint256 amountIn = psm.quoteToSynthGivenOut(amountOut);

        assertEq(amountIn, expectedAmountIn);
    }

    function testSanityPriceConversionToSynth() public {
        uint256 price = 0.25e18;

        uint256 synthAmount = 1e18;
        uint256 underlyingAmount = 0.25e18;

        PegStabilityModule psmNoFee =
            new PegStabilityModule(address(evc), address(synth), address(underlying), 0, 0, price);

        assertEq(psmNoFee.quoteToSynthGivenIn(underlyingAmount), synthAmount);
        assertEq(psmNoFee.quoteToSynthGivenOut(synthAmount), underlyingAmount);
    }

    function testSanityPriceConversionToUnderlying() public {
        uint256 price = 0.25e18;

        uint256 synthAmount = 1e18;
        uint256 underlyingAmount = 0.25e18;

        PegStabilityModule psmNoFee =
            new PegStabilityModule(address(evc), address(synth), address(underlying), 0, 0, price);

        assertEq(psmNoFee.quoteToUnderlyingGivenIn(synthAmount), underlyingAmount);
        assertEq(psmNoFee.quoteToUnderlyingGivenOut(underlyingAmount), synthAmount);
    }
}
