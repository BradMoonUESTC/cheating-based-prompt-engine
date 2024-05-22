// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {REDSTONE_ETH_USD_FEED, REDSTONE_USDC_DAI_FEED} from "test/adapter/redstone/RedstoneFeeds.sol";
import {WETH, USDC, DAI} from "test/utils/EthereumAddresses.sol";
import {ForkTest} from "test/utils/ForkTest.sol";
import {RedstoneCoreOracle} from "src/adapter/redstone/RedstoneCoreOracle.sol";

contract RedstoneCoreOracleForkTest is ForkTest {
    RedstoneCoreOracle oracle;

    function setUp() public {
        _setUpForkLatest();
    }

    function test_UpdatePrice_WETH_USDC() public {
        oracle = new RedstoneCoreOracle(WETH, USDC, REDSTONE_ETH_USD_FEED, 8, 3 minutes);
        (uint256 tsMillis, bytes memory payload) = _fetchRedstonePayload("ETH");
        bytes memory data = abi.encodePacked(abi.encodeCall(oracle.updatePrice, (uint48(tsMillis / 1000))), payload);

        (bool success,) = address(oracle).call(data);
        assertTrue(success);
        uint256 outAmount = oracle.getQuote(1e18, WETH, USDC);
        assertGt(outAmount, 0);
    }

    function test_UpdatePrice_USDC_DAI() public {
        oracle = new RedstoneCoreOracle(USDC, DAI, REDSTONE_USDC_DAI_FEED, 14, 3 minutes);
        (uint256 tsMillis, bytes memory payload) = _fetchRedstonePayload("USDC.DAI");
        bytes memory data = abi.encodePacked(abi.encodeCall(oracle.updatePrice, (uint48(tsMillis / 1000))), payload);

        (bool success,) = address(oracle).call(data);
        assertTrue(success);
        uint256 outAmount = oracle.getQuote(1e6, USDC, DAI);
        assertApproxEqRel(outAmount, 1e18, 0.1e18);
    }

    function test_UpdatePrice_RevertsWhen_WrongFeed() public {
        oracle = new RedstoneCoreOracle(USDC, DAI, REDSTONE_ETH_USD_FEED, 14, 3 minutes);
        (uint256 tsMillis, bytes memory payload) = _fetchRedstonePayload("BTC");
        bytes memory data = abi.encodePacked(abi.encodeCall(oracle.updatePrice, (uint48(tsMillis / 1000))), payload);

        (bool success,) = address(oracle).call(data);
        assertFalse(success);
    }

    function _fetchRedstonePayload(string memory feedSymbol)
        internal
        returns (uint256 tsMillis, bytes memory payload)
    {
        string[] memory cmds = new string[](3);
        cmds[0] = "node";
        cmds[1] = "test/adapter/redstone/get_redstone_payload.js";
        cmds[2] = feedSymbol;
        payload = vm.ffi(cmds);
        assembly {
            tsMillis := shr(208, mload(add(payload, 0x60)))
        }
    }
}
