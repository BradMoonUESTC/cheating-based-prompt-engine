// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/Address.sol";
import {AggregatorV2V3Interface as IChainlinkAggregator} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";

import "../../../../LiquidityMining/CrossChainMsg/libraries/LayerZeroHelper.sol";
import "../../../../interfaces/ILayerZeroEndpoint.sol";
import "../../../../interfaces/IWstETH.sol";
import "../../../libraries/BoringOwnableUpgradeable.sol";

contract PendleChainlinkRelayer {
    uint256 private constant DST_EXECUTION_GAS = 50000;

    address public immutable lzEndpoint;
    address public immutable dstAddress;
    uint256 public immutable dstChainId;
    address public immutable chainlinkFeed;

    constructor(address _lzEndpoint, address _dstAddress, uint256 _dstChainId, address _chainlinkFeed) {
        lzEndpoint = _lzEndpoint;
        dstAddress = _dstAddress;
        dstChainId = _dstChainId;
        chainlinkFeed = _chainlinkFeed;
    }

    function run() external payable {
        bytes memory path = abi.encodePacked(dstAddress, address(this));
        ILayerZeroEndpoint(lzEndpoint).send{value: msg.value}(
            LayerZeroHelper._getLayerZeroChainIds(dstChainId),
            path,
            abi.encode(IChainlinkAggregator(chainlinkFeed).latestAnswer()),
            payable(msg.sender),
            address(0),
            abi.encodePacked(uint16(1), DST_EXECUTION_GAS)
        );
    }
}
