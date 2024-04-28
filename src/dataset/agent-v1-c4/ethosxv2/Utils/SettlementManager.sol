// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ControllerBase} from "../Controller/ControllerBase.sol";

interface ISettlementManager {
    function latestCycleStartTime() external view returns (uint256);

    function cycleScrappingTime() external view returns (uint256);
}

contract SettlementManager is OwnableUpgradeable {
    event SettlementCalled(uint256 last_settlement_time_, uint256 current_settlement_time_, uint256 last_settlement_px_, uint256 current_settlement_px_);

    event CycleScrapped(uint256 last_settlement_time_);

    uint256 public cycle_duration;
    uint256 public scrapping_time;

    IPyth private _pyth;
    bytes32 private _price_id;

    ControllerBase private _controller;

    uint256 private _last_settlement_px;
    uint256 private _last_settlement_time;

    uint64 public update_time_tolerance;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {
        __Ownable_init(msg.sender);
    }

    function __SettlementManager_init(address controller_address_, address price_oracle_address_, bytes32 price_id_, uint256 cycle_duration_, uint256 cycle_scrapping_time_, uint64 update_time_tolerance_) external initializer {
        __Ownable_init(msg.sender);

        _pyth = IPyth(price_oracle_address_);
        _controller = ControllerBase(controller_address_);
        _price_id = price_id_;
        cycle_duration = cycle_duration_;
        scrapping_time = cycle_scrapping_time_;
        update_time_tolerance = update_time_tolerance_;
    }

    function __SettlementManager_reinit(address controller_address_, address price_oracle_address_, bytes32 price_id_, uint256 cycle_duration_, uint256 cycle_scrapping_time_, uint64 update_time_tolerance_) external reinitializer(2) {
        _pyth = IPyth(price_oracle_address_);
        _controller = ControllerBase(controller_address_);
        _price_id = price_id_;

        cycle_duration = cycle_duration_;
        scrapping_time = cycle_scrapping_time_;
        update_time_tolerance = update_time_tolerance_;
    }

    function setLastSettlementTime(uint256 last_settlement_time_) external onlyOwner {
        _last_settlement_time = last_settlement_time_;
    }

    function lastSettlementPrice() public view returns (uint256) {
        return _last_settlement_px;
    }

    function lastSettlementTime() public view returns (uint256) {
        return _last_settlement_time;
    }

    function latestCycleStartTime() external view returns (uint256) {
        uint256 last_settlement_time_ = _last_settlement_time;
        uint256 cycle_duration_ = cycle_duration;

        if (last_settlement_time_ == 0) {
            revert("Cycles not initialized yet");
        }

        return last_settlement_time_ + cycle_duration_ * ((block.timestamp - last_settlement_time_) / cycle_duration_);
    }

    function executeSettlement(bytes[] calldata price_update_data_, uint64 update_time_) external payable {
        uint256 last_settlement_time_ = _last_settlement_time;
        uint256 cycle_duration_ = cycle_duration;

        require(((update_time_ == last_settlement_time_ + cycle_duration_) && (block.timestamp <= last_settlement_time_ + cycle_duration_ + scrapping_time)) || (last_settlement_time_ == 0), "Incorrect update time");

        uint256 fee_ = _pyth.getUpdateFee(price_update_data_);

        bytes32[] memory price_ids_ = new bytes32[](1);
        price_ids_[0] = _price_id;

        PythStructs.PriceFeed memory price_feed_ = (_pyth.parsePriceFeedUpdates{value: fee_}(price_update_data_, price_ids_, update_time_, update_time_ + update_time_tolerance))[0];

        uint256 current_cycle_settlement_price_ = uint256(uint64(price_feed_.price.price));

        _controller.executeSettlement(current_cycle_settlement_price_, update_time_);

        emit SettlementCalled(last_settlement_time_, update_time_, _last_settlement_px, current_cycle_settlement_price_);

        _last_settlement_time = update_time_;
        _last_settlement_px = current_cycle_settlement_price_;
    }

    function cycleScrappingTime() external view returns (uint256) {
        return _last_settlement_time + cycle_duration + scrapping_time;
    }

    function scrapCycle() external {
        uint256 last_settlement_time_ = _last_settlement_time;
        uint256 cycle_duration_ = cycle_duration;

        require(last_settlement_time_ != 0 && block.timestamp > last_settlement_time_ + cycle_duration_ + scrapping_time, "Not the time to scrap the cycle yet");

        _controller.scrapCycle(last_settlement_time_ + cycle_duration_);

        emit CycleScrapped(last_settlement_time_);

        _last_settlement_time = last_settlement_time_ + cycle_duration_;
    }

    uint256[50] private __gap;
}
