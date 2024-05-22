// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {STETH, WSTETH} from "test/utils/EthereumAddresses.sol";
import {ForkTest} from "test/utils/ForkTest.sol";
import {LidoOracle} from "src/adapter/lido/LidoOracle.sol";
import {Errors} from "src/lib/Errors.sol";

contract LidoOracleForkTest is ForkTest {
    LidoOracle oracle;

    function setUp() public {
        _setUpFork(19000000);
        oracle = new LidoOracle();
    }

    function test_GetQuote_Integrity() public view {
        uint256 stEthWstEth = oracle.getQuote(1e18, STETH, WSTETH);
        assertApproxEqRel(stEthWstEth, 0.85e18, 0.1e18);

        uint256 wstEthStEth = oracle.getQuote(1e18, WSTETH, STETH);
        assertApproxEqRel(wstEthStEth, 1.15e18, 0.1e18);
    }

    function test_GetQuotes_Integrity() public view {
        (uint256 stEthWstEthBid, uint256 stEthWstEthAsk) = oracle.getQuotes(1e18, STETH, WSTETH);
        assertApproxEqRel(stEthWstEthBid, 0.85e18, 0.1e18);
        assertApproxEqRel(stEthWstEthAsk, 0.85e18, 0.1e18);

        (uint256 wstEthStEthBid, uint256 wstEthStEthAsk) = oracle.getQuotes(1e18, WSTETH, STETH);
        assertApproxEqRel(wstEthStEthBid, 1.15e18, 0.1e18);
        assertApproxEqRel(wstEthStEthAsk, 1.15e18, 0.1e18);
    }
}
