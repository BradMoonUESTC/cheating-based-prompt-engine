// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {StubPriceOracle} from "test/adapter/StubPriceOracle.sol";
import {CrossAdapter} from "src/adapter/CrossAdapter.sol";

contract CrossAdapterTest is Test {
    address BASE = makeAddr("BASE");
    address CROSS = makeAddr("CROSS");
    address QUOTE = makeAddr("QUOTE");
    StubPriceOracle oracleBaseCross;
    StubPriceOracle oracleCrossQuote;
    CrossAdapter oracle;

    function setUp() public {
        oracleBaseCross = new StubPriceOracle();
        oracleCrossQuote = new StubPriceOracle();
        oracle = new CrossAdapter(BASE, CROSS, QUOTE, address(oracleBaseCross), address(oracleCrossQuote));
    }

    function test_Constructor_Integrity() public view {
        assertEq(oracle.base(), BASE);
        assertEq(oracle.cross(), CROSS);
        assertEq(oracle.quote(), QUOTE);
        assertEq(oracle.oracleBaseCross(), address(oracleBaseCross));
        assertEq(oracle.oracleCrossQuote(), address(oracleCrossQuote));
    }

    function test_GetQuote_Integrity(uint256 inAmount, uint256 priceBaseCross, uint256 priceCrossQuote) public {
        inAmount = bound(inAmount, 0, type(uint128).max);
        priceBaseCross = bound(priceBaseCross, 1, 1e27);
        priceCrossQuote = bound(priceCrossQuote, 1, 1e27);

        oracleBaseCross.setPrice(BASE, CROSS, priceBaseCross);
        oracleCrossQuote.setPrice(CROSS, QUOTE, priceCrossQuote);

        uint256 expectedOutAmount = inAmount * priceBaseCross / 1e18 * priceCrossQuote / 1e18;
        assertEq(oracle.getQuote(inAmount, BASE, QUOTE), expectedOutAmount);
    }

    function test_GetQuote_Integrity_Inverse(uint256 inAmount, uint256 priceQuoteCross, uint256 priceCrossBase)
        public
    {
        inAmount = bound(inAmount, 0, type(uint128).max);
        priceQuoteCross = bound(priceQuoteCross, 1, 1e27);
        priceCrossBase = bound(priceCrossBase, 1, 1e27);

        oracleCrossQuote.setPrice(QUOTE, CROSS, priceQuoteCross);
        oracleBaseCross.setPrice(CROSS, BASE, priceCrossBase);

        uint256 expectedOutAmount = inAmount * priceQuoteCross / 1e18 * priceCrossBase / 1e18;
        assertEq(oracle.getQuote(inAmount, QUOTE, BASE), expectedOutAmount);
    }
}
