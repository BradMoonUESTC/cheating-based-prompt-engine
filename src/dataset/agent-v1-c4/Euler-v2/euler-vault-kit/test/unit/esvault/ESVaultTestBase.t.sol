// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {EVaultTestBase} from "../evault/EVaultTestBase.t.sol";
import {IEVault, IERC20} from "../../../src/EVault/IEVault.sol";
import {IRMTestDefault} from "../../mocks/IRMTestDefault.sol";
import {ESynth} from "../../../src/Synths/ESynth.sol";
import {TestERC20} from "../../mocks/TestERC20.sol";

contract ESVaultTestBase is EVaultTestBase {
    ESynth assetTSTAsSynth;
    ESynth assetTST2AsSynth;

    function setUp() public virtual override {
        super.setUp();

        assetTSTAsSynth = ESynth(address(new ESynth(evc, "Test Synth", "TST")));
        assetTST = TestERC20(address(assetTSTAsSynth));
        assetTST2AsSynth = ESynth(address(new ESynth(evc, "Test Synth 2", "TST2")));
        assetTST2 = TestERC20(address(assetTST2AsSynth));

        eTST = createSynthEVault(address(assetTST));

        // Set the capacity for the vault on the synth
        // assetTSTAsSynth.setCapacity(address(eTST), type(uint128).max);

        eTST2 = createSynthEVault(address(assetTST2));

        // Set the capacity for the vault on the synth
        // assetTST2AsSynth.setCapacity(address(eTST2), type(uint128).max);
    }
}
