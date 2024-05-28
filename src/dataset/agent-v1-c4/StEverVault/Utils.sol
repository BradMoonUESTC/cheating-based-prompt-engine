pragma solidity >=0.7.0 <0.9.0;
library Utils {
    function isValidAddress(address _address) public returns (bool) {
        return _address != address(0);
    }

    function isValidPubKey(uint256 _pubkey) public returns (bool) {
        return _pubkey != 0;
    }
}