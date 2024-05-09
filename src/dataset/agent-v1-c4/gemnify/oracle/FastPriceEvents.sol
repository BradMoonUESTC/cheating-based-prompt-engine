// SPDX-License-Identifier: MIT

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interfaces/IFastPriceEvents.sol";

pragma solidity ^0.8.19;

contract FastPriceEvents is IFastPriceEvents, OwnableUpgradeable {
    mapping(address => bool) public isPriceFeed;
    event PriceUpdate(address token, uint256 price, address priceFeed);

    function initialize() external initializer {
        __Ownable_init();
    }

    function setIsPriceFeed(
        address _priceFeed,
        bool _isPriceFeed
    ) external onlyOwner {
        isPriceFeed[_priceFeed] = _isPriceFeed;
    }

    function emitPriceEvent(address _token, uint256 _price) external override {
        require(isPriceFeed[msg.sender], "FastPriceEvents: invalid sender");
        emit PriceUpdate(_token, _price, msg.sender);
    }
}
