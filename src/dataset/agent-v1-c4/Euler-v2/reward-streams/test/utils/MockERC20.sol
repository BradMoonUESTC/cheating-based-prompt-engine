// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "evc/interfaces/IEthereumVaultConnector.sol";
import "../../src/interfaces/IBalanceTracker.sol";

/// @title IBalanceForwarder
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice This interface defines the functions for enabling and disabling balance forwarding.
interface IBalanceForwarder {
    /// @notice Enables balance forwarding for the msg.sender
    /// @dev Only the msg.sender can enable balance forwarding for itself
    /// @dev Should call the IBalanceTracker hook with the current account's balance
    function enableBalanceForwarding() external;

    /// @notice Disables balance forwarding for the msg.sender
    /// @dev Only the msg.sender can disable balance forwarding for itself
    /// @dev Should call the IBalanceTracker hook with the account's balance of 0
    function disableBalanceForwarding() external;
}

contract MockERC20 is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract MockERC20Malicious is MockERC20 {
    constructor(string memory _name, string memory _symbol) MockERC20(_name, _symbol) {}

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        return super.transferFrom(from, to, amount - 1);
    }
}

contract MockERC20BalanceForwarder is MockERC20, IBalanceForwarder {
    IEVC public immutable evc;
    IBalanceTracker public immutable balanceTracker;

    mapping(address account => bool enabled) internal forwardingEnabled;

    constructor(
        IEVC _evc,
        IBalanceTracker _balanceTracker,
        string memory _name,
        string memory _symbol
    ) MockERC20(_name, _symbol) {
        evc = _evc;
        balanceTracker = _balanceTracker;
    }

    function enableBalanceForwarding() external {
        address account = _msgSender();
        forwardingEnabled[account] = true;
        balanceTracker.balanceTrackerHook(account, balanceOf(account), false);
    }

    function disableBalanceForwarding() external {
        address account = _msgSender();
        forwardingEnabled[account] = false;
        balanceTracker.balanceTrackerHook(account, 0, false);
    }

    function _msgSender() internal view virtual override returns (address msgSender) {
        msgSender = msg.sender;

        if (msgSender == address(evc)) {
            (msgSender,) = evc.getCurrentOnBehalfOfAccount(address(0));
        }

        return msgSender;
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(from, to, value);

        if (forwardingEnabled[from]) {
            balanceTracker.balanceTrackerHook(from, balanceOf(from), evc.isControlCollateralInProgress());
        }

        if (from != to && forwardingEnabled[to]) {
            balanceTracker.balanceTrackerHook(to, balanceOf(to), false);
        }
    }
}
