// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {ForkTest} from "test/utils/ForkTest.sol";
import {CHRONICLE_ETH_USD_FEED} from "test/adapter/chronicle/ChronicleAddresses.sol";
import {WETH, USDC, GUSD, DAI} from "test/utils/EthereumAddresses.sol";
import {ChronicleOracle} from "src/adapter/chronicle/ChronicleOracle.sol";

contract ChronicleOracleForkTest is ForkTest {
    ChronicleOracle oracle;

    function setUp() public {
        _setUpFork(19474200);
        vm.store(
            CHRONICLE_ETH_USD_FEED,
            keccak256(abi.encode(0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f, uint256(2))),
            bytes32(uint256(1))
        );
    }

    function test_ethUsd_USDC() public {
        oracle = new ChronicleOracle(WETH, USDC, CHRONICLE_ETH_USD_FEED, 24 hours);
        assertApproxEqRel(oracle.getQuote(1e18, WETH, USDC), 3100e6, 0.1e18);
        assertApproxEqRel(oracle.getQuote(3100e6, USDC, WETH), 1e18, 0.1e18);
    }

    function test_ethUsd_DAI() public {
        oracle = new ChronicleOracle(WETH, DAI, CHRONICLE_ETH_USD_FEED, 24 hours);
        assertApproxEqRel(oracle.getQuote(1e18, WETH, DAI), 3100e18, 0.1e18);
        assertApproxEqRel(oracle.getQuote(3100e18, DAI, WETH), 1e18, 0.1e18);
    }

    function test_ethUsd_GUSD() public {
        oracle = new ChronicleOracle(WETH, GUSD, CHRONICLE_ETH_USD_FEED, 24 hours);
        assertApproxEqRel(oracle.getQuote(1e18, WETH, GUSD), 3100e2, 0.1e18);
        assertApproxEqRel(oracle.getQuote(3100e2, GUSD, WETH), 1e18, 0.1e18);
    }
}
