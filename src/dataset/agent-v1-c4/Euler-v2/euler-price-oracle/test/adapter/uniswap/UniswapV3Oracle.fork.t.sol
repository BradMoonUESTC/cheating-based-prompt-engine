// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {UNISWAP_V3_FACTORY, UNISWAP_V3_USDC_WETH_500, USDC, WETH} from "test/utils/EthereumAddresses.sol";
import {ForkTest} from "test/utils/ForkTest.sol";
import {UniswapV3Oracle} from "src/adapter/uniswap/UniswapV3Oracle.sol";
import {Errors} from "src/lib/Errors.sol";

contract UniswapV3OracleForkTest is ForkTest {
    UniswapV3Oracle oracle;

    function setUp() public {
        _setUpFork(19000000);
    }

    function test_Constructor_Integrity_PoolAddress() public {
        oracle = new UniswapV3Oracle(USDC, WETH, 500, 15 minutes, UNISWAP_V3_FACTORY);
        assertEq(oracle.pool(), UNISWAP_V3_USDC_WETH_500);

        oracle = new UniswapV3Oracle(WETH, USDC, 500, 15 minutes, UNISWAP_V3_FACTORY);
        assertEq(oracle.pool(), UNISWAP_V3_USDC_WETH_500);
    }

    function test_GetQuote_Integrity() public {
        oracle = new UniswapV3Oracle(USDC, WETH, 500, 15 minutes, UNISWAP_V3_FACTORY);

        uint256 usdcWeth = oracle.getQuote(2500e6, USDC, WETH);
        assertApproxEqRel(usdcWeth, 1e18, 0.1e18);

        uint256 wethUsdc = oracle.getQuote(1e18, WETH, USDC);
        assertApproxEqRel(wethUsdc, 2500e6, 0.1e18);
    }

    function test_GetQuotes_Integrity() public {
        oracle = new UniswapV3Oracle(USDC, WETH, 500, 15 minutes, UNISWAP_V3_FACTORY);

        (uint256 usdcWethBid, uint256 usdcWethAsk) = oracle.getQuotes(2500e6, USDC, WETH);
        assertApproxEqRel(usdcWethBid, 1e18, 0.1e18);
        assertApproxEqRel(usdcWethAsk, 1e18, 0.1e18);

        (uint256 wethUsdcBid, uint256 wethUsdcAsk) = oracle.getQuotes(1e18, WETH, USDC);
        assertApproxEqRel(wethUsdcBid, 2500e6, 0.1e18);
        assertApproxEqRel(wethUsdcAsk, 2500e6, 0.1e18);
    }
}
