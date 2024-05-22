// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {ForkTest} from "test/utils/ForkTest.sol";
import {
    CHAINLINK_BTC_ETH_FEED,
    CHAINLINK_USDC_ETH_FEED,
    CHAINLINK_STETH_ETH_FEED,
    CHAINLINK_ETH_USD_FEED
} from "test/adapter/chainlink/ChainlinkAddresses.sol";
import {WETH, STETH, WBTC, USDC, GUSD, DAI} from "test/utils/EthereumAddresses.sol";
import {ChainlinkOracle} from "src/adapter/chainlink/ChainlinkOracle.sol";

contract ChainlinkOracleForkTest is ForkTest {
    ChainlinkOracle oracle;

    function setUp() public {
        _setUpFork(18888888);
    }

    function test_btcEth() public {
        oracle = new ChainlinkOracle(WBTC, WETH, CHAINLINK_BTC_ETH_FEED, 24 hours);
        assertApproxEqRel(oracle.getQuote(0.06e8, WBTC, WETH), 1e18, 0.1e18);
        assertApproxEqRel(oracle.getQuote(17e18, WETH, WBTC), 1e8, 0.1e18);
    }

    function test_usdcEth() public {
        oracle = new ChainlinkOracle(USDC, WETH, CHAINLINK_USDC_ETH_FEED, 24 hours);
        assertApproxEqRel(oracle.getQuote(2500e6, USDC, WETH), 1e18, 0.1e18);
        assertApproxEqRel(oracle.getQuote(1e18, WETH, USDC), 2500e6, 0.1e18);
    }

    function test_stEthEth() public {
        oracle = new ChainlinkOracle(STETH, WETH, CHAINLINK_STETH_ETH_FEED, 24 hours);
        assertApproxEqRel(oracle.getQuote(1e18, STETH, WETH), 1e18, 0.1e18);
        assertApproxEqRel(oracle.getQuote(1e18, WETH, STETH), 1e18, 0.1e18);
    }

    function test_ethUsd_USDC() public {
        oracle = new ChainlinkOracle(WETH, USDC, CHAINLINK_ETH_USD_FEED, 24 hours);
        assertApproxEqRel(oracle.getQuote(1e18, WETH, USDC), 2500e6, 0.1e18);
        assertApproxEqRel(oracle.getQuote(2500e6, USDC, WETH), 1e18, 0.1e18);
    }

    function test_ethUsd_DAI() public {
        oracle = new ChainlinkOracle(WETH, DAI, CHAINLINK_ETH_USD_FEED, 24 hours);
        assertApproxEqRel(oracle.getQuote(1e18, WETH, DAI), 2500e18, 0.1e18);
        assertApproxEqRel(oracle.getQuote(2500e18, DAI, WETH), 1e18, 0.1e18);
    }

    function test_ethUsd_GUSD() public {
        oracle = new ChainlinkOracle(WETH, GUSD, CHAINLINK_ETH_USD_FEED, 24 hours);
        assertApproxEqRel(oracle.getQuote(1e18, WETH, GUSD), 2500e2, 0.1e18);
        assertApproxEqRel(oracle.getQuote(2500e2, GUSD, WETH), 1e18, 0.1e18);
    }
}
