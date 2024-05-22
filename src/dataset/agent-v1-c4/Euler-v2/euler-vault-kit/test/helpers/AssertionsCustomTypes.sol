// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../../src/EVault/shared/types/Types.sol";
import "forge-std/StdAssertions.sol";

/// @notice assertion helpers for custom types
contract AssertionsCustomTypes is StdAssertions {
    Assets constant ZERO_ASSETS = Assets.wrap(0);
    Shares constant ZERO_SHARES = Shares.wrap(0);
    Owed constant ZERO_OWED = Owed.wrap(0);

    Assets constant MAX_ASSETS = Assets.wrap(uint112(MAX_SANE_AMOUNT));
    Shares constant MAX_SHARES = Shares.wrap(uint112(MAX_SANE_AMOUNT));
    Owed constant MAX_OWED = Owed.wrap(uint144(MAX_SANE_DEBT_AMOUNT));

    function assertEq(Assets a, Assets b) internal pure {
        assertEq(Assets.unwrap(a), Assets.unwrap(b));
    }

    function assertEq(Assets a, Assets b, string memory err) internal pure {
        assertEq(Assets.unwrap(a), Assets.unwrap(b), err);
    }

    function assertEq(Shares a, Shares b) internal pure {
        assertEq(Shares.unwrap(a), Shares.unwrap(b));
    }

    function assertEq(Shares a, Shares b, string memory err) internal pure {
        assertEq(Shares.unwrap(a), Shares.unwrap(b), err);
    }

    function assertEq(Owed a, Owed b) internal pure {
        assertEq(Owed.unwrap(a), Owed.unwrap(b));
    }

    function assertEq(Owed a, Owed b, string memory err) internal pure {
        assertEq(Owed.unwrap(a), Owed.unwrap(b), err);
    }
}
