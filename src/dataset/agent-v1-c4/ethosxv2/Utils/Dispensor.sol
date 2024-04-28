// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../Tokens/ProxyUSDC.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract Dispenser is OwnableUpgradeable {
    event FundsDispensed(address indexed dispense_address_);

    mapping(address => uint256) private _last_dispensed;

    uint256 private _usdc_amount_per_address;
    uint256 private _eth_amount_per_address;

    uint256 private _cooloff_period;

    ProxyUSDC private _usdc;

    function __Dispenser_init(address _usdc_address) public initializer {
        __Ownable_init(msg.sender);
        _usdc = ProxyUSDC(_usdc_address);
        _usdc_amount_per_address = 5 ether;
        _eth_amount_per_address = 10 ** 16;
        _cooloff_period = 1 days;
    }

    receive() external payable {}

    function setUSDCAmountPerAddress(uint256 usdc_amount_per_address_) public onlyOwner {
        _usdc_amount_per_address = usdc_amount_per_address_;
    }

    function setEthAmountPerAddress(uint256 eth_amount_per_address_) public onlyOwner {
        _eth_amount_per_address = eth_amount_per_address_;
    }

    function setCooloffPeriod(uint256 cooloff_period_) public onlyOwner {
        _cooloff_period = cooloff_period_;
    }

    function alreadyDispensedTo(address address_) external view returns (bool) {
        return block.timestamp - _last_dispensed[address_] < _cooloff_period;
    }

    function withdrawFunds() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
        _usdc.transfer(owner(), _usdc.balanceOf(address(this)));
    }

    function dispense(address dispense_address_) public onlyOwner {
        require(block.timestamp - _last_dispensed[dispense_address_] >= _cooloff_period, "Already dispensed");

        require(_usdc.balanceOf(address(this)) > _usdc_amount_per_address, "Ran out of USDC");

        require(address(this).balance > _eth_amount_per_address, "Ran out of ETH");

        _usdc.transfer(dispense_address_, _usdc_amount_per_address);

        (bool success_, ) = address(dispense_address_).call{value: _eth_amount_per_address}("");

        require(success_, "Transfer failed");

        _last_dispensed[dispense_address_] = block.timestamp;

        emit FundsDispensed(dispense_address_);
    }
}
