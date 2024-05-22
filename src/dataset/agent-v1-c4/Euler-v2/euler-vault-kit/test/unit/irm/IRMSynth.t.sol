// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import "../../../src/Synths/IRMSynth.sol";
import "../../mocks/MockPriceOracle.sol";
import "../../mocks/MockDecimals.sol";

contract IRMSynthTest is Test {
    IRMSynth public irm;
    MockPriceOracle public oracle;

    address public synth;
    address public REFERENCE_ASSET = makeAddr("referenceAsset");
    uint256 public TARGET_QUOTE = 1e18;

    function setUp() public {
        synth = address(new MockDecimals(18));
        oracle = new MockPriceOracle();
        oracle.setPrice(synth, REFERENCE_ASSET, 1e18);

        irm = new IRMSynth(synth, REFERENCE_ASSET, address(oracle), TARGET_QUOTE);
    }

    function test_IRMSynth_Constructor_SynthZeroAddress() public {
        vm.expectRevert(IRMSynth.E_ZeroAddress.selector);
        new IRMSynth(address(0), REFERENCE_ASSET, address(oracle), TARGET_QUOTE);
    }

    function test_IRMSynth_Constructor_ReferenceAssetZeroAddress() public {
        vm.expectRevert(IRMSynth.E_ZeroAddress.selector);
        new IRMSynth(synth, address(0), address(oracle), TARGET_QUOTE);
    }

    function test_IRMSynth_Constructor_OracleZeroAddress() public {
        vm.expectRevert(IRMSynth.E_ZeroAddress.selector);
        new IRMSynth(synth, REFERENCE_ASSET, address(0), TARGET_QUOTE);
    }

    function testIRMSynth_Constructor_TargetQuote() public view {
        assertEq(irm.targetQuote(), TARGET_QUOTE);
    }

    function test_IRMSynth_Constructor_QuoteAmount() public {
        // Should be 1e18 with 18 decimal token
        assertEq(irm.quoteAmount(), 10 ** 18);

        // Should be 1e6 with 6 decimal token
        MockDecimals sixDecimals = new MockDecimals(6);
        oracle.setPrice(address(sixDecimals), REFERENCE_ASSET, 1e18);
        IRMSynth irmSixDecimals = new IRMSynth(address(sixDecimals), REFERENCE_ASSET, address(oracle), 1e6);
        assertEq(irmSixDecimals.quoteAmount(), 10 ** 6);
    }

    function test_IRMSynth_Constructor_InvalidQuote() public {
        MockPriceOracle invalidOracle = new MockPriceOracle();
        vm.expectRevert(IRMSynth.E_InvalidQuote.selector);
        new IRMSynth(synth, REFERENCE_ASSET, address(invalidOracle), TARGET_QUOTE);
    }

    function test_IRMSynth_InitialRate() public {
        assertEq(irm.computeInterestRate(address(0), 0, 0), uint216(irm.BASE_RATE()));
    }

    function test_IRMSynth_AjustInterval() public {
        uint256 adjustInterval = irm.ADJUST_INTERVAL();
        skip(adjustInterval);
        irm.computeInterestRate(address(0), 0, 0);
        uint256 lastUpdatedBefore = irm.getIRMData().lastUpdated;
        assertEq(lastUpdatedBefore, block.timestamp);
        skip(adjustInterval / 2);
        irm.computeInterestRate(address(0), 0, 0);
        uint256 lastUpdatedAfter = irm.getIRMData().lastUpdated;
        assertEq(lastUpdatedAfter, lastUpdatedBefore);
    }

    function testIRMSynth_RateAdjustUp() public {
        oracle.setPrice(synth, REFERENCE_ASSET, irm.targetQuote() / 2);

        IRMSynth.IRMData memory irmDataBefore = irm.getIRMData();
        skip(irm.ADJUST_INTERVAL());
        irm.computeInterestRate(address(0), 0, 0);
        IRMSynth.IRMData memory irmDataAfter = irm.getIRMData();

        // Should have updated the rate and last updated
        assertEq(irmDataAfter.lastUpdated, block.timestamp);
        assertEq(irmDataAfter.lastRate, irmDataBefore.lastRate * irm.ADJUST_FACTOR() / irm.ADJUST_ONE());
    }

    function test_IRMSynth_RateAdjustDown() public {
        // adjust the rate up first two times
        oracle.setPrice(synth, REFERENCE_ASSET, irm.targetQuote() / 2);
        skip(irm.ADJUST_INTERVAL());
        irm.computeInterestRate(address(0), 0, 0);
        skip(irm.ADJUST_INTERVAL());
        irm.computeInterestRate(address(0), 0, 0);

        oracle.setPrice(synth, REFERENCE_ASSET, irm.targetQuote() * 2);
        IRMSynth.IRMData memory irmDataBefore = irm.getIRMData();
        skip(irm.ADJUST_INTERVAL());
        irm.computeInterestRate(address(0), 0, 0);
        IRMSynth.IRMData memory irmDataAfter = irm.getIRMData();

        // Should have updated the rate and last updated
        assertEq(irmDataAfter.lastUpdated, block.timestamp);
        assertEq(irmDataAfter.lastRate, irmDataBefore.lastRate * irm.ADJUST_ONE() / irm.ADJUST_FACTOR());
    }

    function test_IRMSynth_RateMinimum() public {
        oracle.setPrice(synth, REFERENCE_ASSET, irm.targetQuote() * 2);

        // Rate already at minimum, try to adjust regardless
        skip(irm.ADJUST_INTERVAL());
        IRMSynth.IRMData memory irmDataBefore = irm.getIRMData();
        irm.computeInterestRate(address(0), 0, 0);
        IRMSynth.IRMData memory irmDataAfter = irm.getIRMData();

        // Rate should not have changed but last updated should have
        assertEq(irmDataAfter.lastUpdated, block.timestamp);
        assertEq(irmDataAfter.lastRate, irmDataBefore.lastRate);
    }

    function test_IRMSynth_RateMax() public {
        oracle.setPrice(synth, REFERENCE_ASSET, irm.targetQuote() / 2);

        // Loop till at max rate
        uint256 maxRate = irm.MAX_RATE();
        while (irm.getIRMData().lastRate < maxRate) {
            skip(irm.ADJUST_INTERVAL());
            irm.computeInterestRate(address(0), 0, 0);
        }

        skip(irm.ADJUST_INTERVAL());
        IRMSynth.IRMData memory irmDataBefore = irm.getIRMData();
        irm.computeInterestRate(address(0), 0, 0);
        IRMSynth.IRMData memory irmDataAfter = irm.getIRMData();

        // Rate should not have changed but last updated should have
        assertEq(irmDataAfter.lastUpdated, block.timestamp);
        assertEq(irmDataAfter.lastRate, irmDataBefore.lastRate);
    }

    function test_computeInterestRateView() public {
        oracle.setPrice(synth, REFERENCE_ASSET, irm.targetQuote() / 2);

        uint256 rate = irm.computeInterestRateView(address(0), 0, 0);
        irm.computeInterestRate(address(0), 0, 0);
        IRMSynth.IRMData memory irmData = irm.getIRMData();

        assertEq(rate, irmData.lastRate);

        skip(irm.ADJUST_INTERVAL());
        rate = irm.computeInterestRateView(address(0), 0, 0);
        irmData = irm.getIRMData();

        assertNotEq(rate, irmData.lastRate);

        irm.computeInterestRate(address(0), 0, 0);
        irmData = irm.getIRMData();

        assertEq(rate, irmData.lastRate);
    }
}
