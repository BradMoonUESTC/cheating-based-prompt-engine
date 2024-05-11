// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Governable} from "./Governable.sol";

abstract contract FToken is ERC20Upgradeable, Governable {
    address public bridge;

    mapping(address user => bool blocked) public userBlocked;

    event UserLocked(address indexed user);
    event UserUnlocked(address indexed user);

    event BridgeUpdated(address indexed newBridge, address indexed oldBridge);

    modifier onlyBridge() {
        require(msg.sender == bridge, "Caller not bridge");
        _;
    }

    function __FToken_init(
        address _owner,
        address _bridge,
        string memory _name,
        string memory _symbol
    ) internal onlyInitializing {
        __ERC20_init(_name, _symbol);
        __Governable_init(_owner);
        bridge = _bridge;
    }

    function lockUser(address _user) external onlyOwner {
        userBlocked[_user] = true;
        emit UserLocked(_user);
    }

    function unlockUser(address _user) external onlyOwner {
        userBlocked[_user] = false;
        emit UserUnlocked(_user);
    }

    function setBridge(address _bridge) external onlyOwner {
        address oldBridge = bridge;
        bridge = _bridge;
        emit BridgeUpdated(_bridge, oldBridge);
    }

    function mint(address to, uint256 amount) external onlyBridge {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyBridge {
        _burn(from, amount);
    }

    function payFee(
        address payer,
        address feeRecipient,
        uint256 amount
    ) external onlyBridge {
        _transfer(payer, feeRecipient, amount);
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override whenNotPaused {
        require(!userBlocked[from], "from is blocked");
        require(!userBlocked[to], "to is blocked");
        super._update(from, to, value);
    }

    uint256[50] private __gap;
}
