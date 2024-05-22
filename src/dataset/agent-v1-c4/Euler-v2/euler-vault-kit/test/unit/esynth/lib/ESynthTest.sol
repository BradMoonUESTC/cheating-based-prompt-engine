// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../../evault/EVaultTestBase.t.sol";
import {IEVault, IERC20} from "../../../../src/EVault/IEVault.sol";
import {IRMTestDefault} from "../../../mocks/IRMTestDefault.sol";
import {ESynth} from "../../../../src/Synths/ESynth.sol";
import {TestERC20} from "../../../mocks/TestERC20.sol";

contract ESynthTest is EVaultTestBase {
    ESynth esynth;
    address user1;
    address user2;

    function setUp() public virtual override {
        super.setUp();

        user1 = vm.addr(1001);
        user2 = vm.addr(1002);

        esynth = ESynth(address(new ESynth(evc, "Test Synth", "TST")));
        assetTST = TestERC20(address(esynth));

        eTST = createSynthEVault(address(assetTST));
    }
}
