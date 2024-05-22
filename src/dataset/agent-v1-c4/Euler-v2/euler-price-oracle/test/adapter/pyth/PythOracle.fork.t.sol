// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {IPyth} from "@pyth/IPyth.sol";
import {PythStructs} from "@pyth/PythStructs.sol";
import {PYTH, PYTH_ETH_USD_FEED} from "test/adapter/pyth/PythFeeds.sol";
import {WETH, USD, DAI} from "test/utils/EthereumAddresses.sol";
import {ForkTest} from "test/utils/ForkTest.sol";
import {PythOracle} from "src/adapter/pyth/PythOracle.sol";

contract PythOracleForkTest is ForkTest {
    using stdStorage for StdStorage;

    PythOracle oracle;

    function setUp() public {
        _setUpFork(19000000);
    }

    function test_GetQuote_Integrity_WETH_USD() public {
        oracle = new PythOracle(PYTH, WETH, USD, PYTH_ETH_USD_FEED, 15 minutes, 500);
        PythStructs.Price memory p = IPyth(PYTH).getPriceUnsafe(PYTH_ETH_USD_FEED);
        p.publishTime = block.timestamp - 5 minutes;
        vm.mockCall(PYTH, abi.encodeCall(IPyth.getPriceUnsafe, (PYTH_ETH_USD_FEED)), abi.encode(p));

        uint256 outAmount = oracle.getQuote(1e18, WETH, USD);
        assertApproxEqRel(outAmount, 2500e18, 0.1e18);
        uint256 outAmountInverse = oracle.getQuote(2500e18, USD, WETH);
        assertApproxEqRel(outAmountInverse, 1e18, 0.1e18);
    }

    function test_GetQuotes_Integrity_WETH_USD() public {
        oracle = new PythOracle(PYTH, WETH, USD, PYTH_ETH_USD_FEED, 15 minutes, 500);
        PythStructs.Price memory p = IPyth(PYTH).getPriceUnsafe(PYTH_ETH_USD_FEED);
        p.publishTime = block.timestamp - 5 minutes;
        vm.mockCall(PYTH, abi.encodeCall(IPyth.getPriceUnsafe, (PYTH_ETH_USD_FEED)), abi.encode(p));

        (uint256 bidOutAmount, uint256 askOutAmount) = oracle.getQuotes(1e18, WETH, USD);
        assertApproxEqRel(bidOutAmount, 2500e18, 0.1e18);
        assertApproxEqRel(askOutAmount, 2500e18, 0.1e18);
        assertEq(bidOutAmount, askOutAmount);

        (uint256 bidOutAmountInverse, uint256 askOutAmountInverse) = oracle.getQuotes(2500e18, USD, WETH);
        assertApproxEqRel(bidOutAmountInverse, 1e18, 0.1e18);
        assertApproxEqRel(askOutAmountInverse, 1e18, 0.1e18);
        assertEq(bidOutAmountInverse, askOutAmountInverse);
    }
}
