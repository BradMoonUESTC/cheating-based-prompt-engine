// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

///@notice https://github.com/one-hundred-proof/kyberswap-exploit/blob/main/lib/helpers/Pretty.sol
library Strings {
    function concat(string memory _base, string memory _value) internal pure returns (string memory) {
        bytes memory _baseBytes = bytes(_base);
        bytes memory _valueBytes = bytes(_value);

        string memory _tmpValue = new string(_baseBytes.length + _valueBytes.length);
        bytes memory _newValue = bytes(_tmpValue);

        uint256 i;
        uint256 j;

        for (i = 0; i < _baseBytes.length; i++) {
            _newValue[j++] = _baseBytes[i];
        }

        for (i = 0; i < _valueBytes.length; i++) {
            _newValue[j++] = _valueBytes[i];
        }

        return string(_newValue);
    }
}

library Pretty {
    uint8 constant DEFAULT_DECIMALS = 18;

    function toBitString(uint256 n) external pure returns (string memory) {
        return uintToBitString(n, 256);
    }

    function toBitString(uint256 n, uint8 decimals) external pure returns (string memory) {
        return uintToBitString(n, decimals);
    }

    function pretty(uint256 n) external pure returns (string memory) {
        return n == type(uint256).max
            ? "type(uint256).max"
            : n == type(uint128).max ? "type(uint128).max" : _pretty(n, DEFAULT_DECIMALS);
    }

    function pretty(bool value) external pure returns (string memory) {
        return value ? "true" : "false";
    }

    function pretty(uint256 n, uint8 decimals) external pure returns (string memory) {
        return _pretty(n, decimals);
    }

    function pretty(int256 n) external pure returns (string memory) {
        return _prettyInt(n, DEFAULT_DECIMALS);
    }

    function pretty(int256 n, uint8 decimals) external pure returns (string memory) {
        return _prettyInt(n, decimals);
    }

    function _pretty(uint256 n, uint8 decimals) internal pure returns (string memory) {
        bool pastDecimals = decimals == 0;
        uint256 place = 0;
        uint256 r; // remainder
        string memory s = "";

        while (n != 0) {
            r = n % 10;
            n /= 10;
            place++;
            s = Strings.concat(toDigit(r), s);
            if (pastDecimals && place % 3 == 0 && n != 0) {
                s = Strings.concat("_", s);
            }
            if (!pastDecimals && place == decimals) {
                pastDecimals = true;
                place = 0;
                s = Strings.concat("_", s);
            }
        }
        if (pastDecimals && place == 0) {
            s = Strings.concat("0", s);
        }
        if (!pastDecimals) {
            uint256 i;
            uint256 upper = (decimals >= place ? decimals - place : 0);
            for (i = 0; i < upper; ++i) {
                s = Strings.concat("0", s);
            }
            s = Strings.concat("0_", s);
        }
        return s;
    }

    function _prettyInt(int256 n, uint8 decimals) internal pure returns (string memory) {
        bool isNegative = n < 0;
        string memory s = "";
        if (isNegative) {
            s = "-";
        }
        return Strings.concat(s, _pretty(uint256(isNegative ? -n : n), decimals));
    }

    function toDigit(uint256 n) internal pure returns (string memory) {
        if (n == 0) {
            return "0";
        } else if (n == 1) {
            return "1";
        } else if (n == 2) {
            return "2";
        } else if (n == 3) {
            return "3";
        } else if (n == 4) {
            return "4";
        } else if (n == 5) {
            return "5";
        } else if (n == 6) {
            return "6";
        } else if (n == 7) {
            return "7";
        } else if (n == 8) {
            return "8";
        } else if (n == 9) {
            return "9";
        } else {
            revert("Not in range 0 to 10");
        }
    }

    function uintToBitString(uint256 n, uint16 bits) internal pure returns (string memory) {
        string memory s = "";
        for (uint256 i; i < bits; i++) {
            if (n % 2 == 0) {
                s = Strings.concat("0", s);
            } else {
                s = Strings.concat("1", s);
            }
            n = n / 2;
        }
        return s;
    }
}
