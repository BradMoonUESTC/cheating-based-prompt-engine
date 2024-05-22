// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

contract MockMinimalStatusCheck {
    bool public shouldFail;

    function setShouldFail(bool shouldPass_) external {
        shouldFail = shouldPass_;
    }

    function checkAccountStatus(address, address[] calldata) external view returns (bytes4 magicValue) {
        require(!shouldFail, "MockMinimalStatusCheck: account status check failed");
        return this.checkAccountStatus.selector;
    }
}
