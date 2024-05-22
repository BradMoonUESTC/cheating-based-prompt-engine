// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {AdapterHelper} from "test/adapter/AdapterHelper.sol";
import {StubStEth} from "test/adapter/lido/StubStEth.sol";
import {STETH} from "test/utils/EthereumAddresses.sol";
import {LidoOracle} from "src/adapter/lido/LidoOracle.sol";

contract LidoOracleHelper is AdapterHelper {
    struct FuzzableState {
        // Answer
        uint256 rate;
        uint256 inAmount;
    }

    function setUpState(FuzzableState memory s) internal {
        s.rate = bound(s.rate, 1e18, 1e27);

        vm.etch(STETH, address(new StubStEth()).code);
        oracle = address(new LidoOracle());

        s.inAmount = bound(s.inAmount, 1, type(uint128).max);

        if (behaviors[Behavior.FeedReverts]) {
            StubStEth(STETH).setRevert(true);
        } else {
            StubStEth(STETH).setRate(s.rate);
        }
    }
}
