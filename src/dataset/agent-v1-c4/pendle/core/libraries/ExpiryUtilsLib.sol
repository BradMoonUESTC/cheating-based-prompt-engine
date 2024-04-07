// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

library ExpiryUtils {
    struct Date {
        uint16 year;
        uint8 month;
        uint8 day;
    }

    uint256 private constant DAY_IN_SECONDS = 86400;
    uint256 private constant YEAR_IN_SECONDS = 31536000;
    uint256 private constant LEAP_YEAR_IN_SECONDS = 31622400;
    uint16 private constant ORIGIN_YEAR = 1970;

    /**
     * @notice Concatenates a Pendle token name/symbol, a yield token name/symbol,
     *         and an expiry, using a delimiter (usually "-" or " ").
     * @param _bt The Pendle token name/symbol.
     * @param _yt The yield token name/symbol.
     * @param _expiry The expiry in epoch time.
     * @param _delimiter Can be any delimiter, but usually "-" or " ".
     * @return result Returns the concatenated string.
     **/
    function concat(
        string memory _bt,
        string memory _yt,
        uint256 _expiry,
        string memory _delimiter
    ) internal pure returns (string memory result) {
        result = string(abi.encodePacked(_bt, _delimiter, _yt, _delimiter, toRFC2822String(_expiry)));
    }

    function toRFC2822String(uint256 _timestamp) internal pure returns (string memory s) {
        Date memory d = parseTimestamp(_timestamp);
        string memory day = uintToString(d.day);
        string memory month = monthName(d);
        string memory year = uintToString(d.year);
        s = string(abi.encodePacked(day, month, year));
    }

    function getDaysInMonth(uint8 _month, uint16 _year) private pure returns (uint8) {
        if (_month == 1 || _month == 3 || _month == 5 || _month == 7 || _month == 8 || _month == 10 || _month == 12) {
            return 31;
        } else if (_month == 4 || _month == 6 || _month == 9 || _month == 11) {
            return 30;
        } else if (isLeapYear(_year)) {
            return 29;
        } else {
            return 28;
        }
    }

    function getYear(uint256 _timestamp) private pure returns (uint16) {
        uint256 secondsAccountedFor = 0;
        uint16 year;
        uint256 numLeapYears;

        // Year
        year = uint16(ORIGIN_YEAR + _timestamp / YEAR_IN_SECONDS);
        numLeapYears = leapYearsBefore(year) - leapYearsBefore(ORIGIN_YEAR);

        secondsAccountedFor += LEAP_YEAR_IN_SECONDS * numLeapYears;
        secondsAccountedFor += YEAR_IN_SECONDS * (year - ORIGIN_YEAR - numLeapYears);

        while (secondsAccountedFor > _timestamp) {
            if (isLeapYear(uint16(year - 1))) {
                secondsAccountedFor -= LEAP_YEAR_IN_SECONDS;
            } else {
                secondsAccountedFor -= YEAR_IN_SECONDS;
            }
            year -= 1;
        }
        return year;
    }

    function isLeapYear(uint16 _year) private pure returns (bool) {
        return ((_year % 4 == 0) && (_year % 100 != 0)) || (_year % 400 == 0);
    }

    function leapYearsBefore(uint256 _year) private pure returns (uint256) {
        _year -= 1;
        return _year / 4 - _year / 100 + _year / 400;
    }

    function monthName(Date memory d) private pure returns (string memory) {
        string[12] memory months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
        return months[d.month - 1];
    }

    function parseTimestamp(uint256 _timestamp) private pure returns (Date memory d) {
        uint256 secondsAccountedFor = 0;
        uint256 buf;
        uint8 i;

        // Year
        d.year = getYear(_timestamp);
        buf = leapYearsBefore(d.year) - leapYearsBefore(ORIGIN_YEAR);

        secondsAccountedFor += LEAP_YEAR_IN_SECONDS * buf;
        secondsAccountedFor += YEAR_IN_SECONDS * (d.year - ORIGIN_YEAR - buf);

        // Month
        uint256 secondsInMonth;
        for (i = 1; i <= 12; i++) {
            secondsInMonth = DAY_IN_SECONDS * getDaysInMonth(i, d.year);
            if (secondsInMonth + secondsAccountedFor > _timestamp) {
                d.month = i;
                break;
            }
            secondsAccountedFor += secondsInMonth;
        }

        // Day
        for (i = 1; i <= getDaysInMonth(d.month, d.year); i++) {
            if (DAY_IN_SECONDS + secondsAccountedFor > _timestamp) {
                d.day = i;
                break;
            }
            secondsAccountedFor += DAY_IN_SECONDS;
        }
    }

    function uintToString(uint256 _i) private pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len - 1;
        while (_i != 0) {
            bstr[k] = bytes1(uint8(48 + (_i % 10)));
            if (k != 0) k--;
            _i /= 10;
        }
        return string(bstr);
    }
}
