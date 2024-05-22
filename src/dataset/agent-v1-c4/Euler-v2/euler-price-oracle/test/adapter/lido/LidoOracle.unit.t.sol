// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {LidoOracleHelper} from "test/adapter/lido/LidoOracleHelper.sol";
import {STETH, WSTETH} from "test/utils/EthereumAddresses.sol";
import {boundAddr} from "test/utils/TestUtils.sol";
import {IStEth} from "src/adapter/lido/IStEth.sol";
import {LidoOracle} from "src/adapter/lido/LidoOracle.sol";
import {Errors} from "src/lib/Errors.sol";

contract LidoOracleTest is LidoOracleHelper {
    function test_Constructor_Integrity(FuzzableState memory s) public {
        setUpState(s);
        assertEq(LidoOracle(oracle).STETH(), STETH);
        assertEq(LidoOracle(oracle).WSTETH(), WSTETH);
    }

    function test_Quote_RevertsWhen_InvalidTokens(FuzzableState memory s, address otherA, address otherB) public {
        setUpState(s);
        otherA = boundAddr(otherA);
        otherB = boundAddr(otherB);
        vm.assume(otherA != WSTETH && otherA != STETH);
        vm.assume(otherB != WSTETH && otherB != STETH);
        expectNotSupported(s.inAmount, WSTETH, WSTETH);
        expectNotSupported(s.inAmount, STETH, STETH);
        expectNotSupported(s.inAmount, WSTETH, otherA);
        expectNotSupported(s.inAmount, otherA, WSTETH);
        expectNotSupported(s.inAmount, STETH, otherA);
        expectNotSupported(s.inAmount, otherA, STETH);
        expectNotSupported(s.inAmount, otherA, otherA);
        expectNotSupported(s.inAmount, otherA, otherB);
    }

    function test_Quote_RevertsWhen_StEthCallReverts(FuzzableState memory s) public {
        setBehavior(Behavior.FeedReverts, true);
        setUpState(s);
        expectRevertForAllQuotePermutations(s.inAmount, STETH, WSTETH, "");
    }

    function test_Quote_StEth_WstEth_Integrity(FuzzableState memory s) public {
        setUpState(s);

        uint256 expectedOutAmount = s.inAmount * 1e18 / s.rate;

        uint256 outAmount = LidoOracle(oracle).getQuote(s.inAmount, STETH, WSTETH);
        assertEq(outAmount, expectedOutAmount);

        (uint256 bidOutAmount, uint256 askOutAmount) = LidoOracle(oracle).getQuotes(s.inAmount, STETH, WSTETH);
        assertEq(bidOutAmount, expectedOutAmount);
        assertEq(askOutAmount, expectedOutAmount);
    }

    function test_Quote_WstEth_StEth_Integrity(FuzzableState memory s) public {
        setUpState(s);

        uint256 expectedOutAmount = s.inAmount * s.rate / 1e18;

        uint256 outAmount = LidoOracle(oracle).getQuote(s.inAmount, WSTETH, STETH);
        assertEq(outAmount, expectedOutAmount);

        (uint256 bidOutAmount, uint256 askOutAmount) = LidoOracle(oracle).getQuotes(s.inAmount, WSTETH, STETH);
        assertEq(bidOutAmount, expectedOutAmount);
        assertEq(askOutAmount, expectedOutAmount);
    }
}
