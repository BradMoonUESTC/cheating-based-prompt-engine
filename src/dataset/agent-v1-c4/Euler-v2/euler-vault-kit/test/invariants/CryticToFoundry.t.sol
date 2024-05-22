// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Errors} from "../../src/EVault/shared/Errors.sol";

// Test Contracts
import {Invariants} from "./Invariants.t.sol";
import {Setup} from "./Setup.t.sol";

/// @title CryticToFoundry
/// @notice Foundry wrapper for fuzzer failed call sequences
/// @dev Regression testing for failed call sequences
contract CryticToFoundry is Invariants, Setup {
    modifier setup() override {
        _;
    }

    /// @dev Foundry compatibility faster setup debugging
    function setUp() public {
        // Deploy protocol contracts and protocol actors
        _setUp();

        // Deploy actors
        _setUpActors();

        // Initialize handler contracts
        _setUpHandlers();

        actor = actors[USER1];
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                 BROKEN INVARIANTS REPLAY                                  //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_I_INVARIANT_A() public {
        vm.expectRevert(Errors.E_BadFee.selector);
        this.setInterestFee(101);
        echidna_I_INVARIANT();
    }

    function test_BM_INVARIANT_G() public {
        // PASS
        this.assert_BM_INVARIANT_G();
    }

    function test_BASE_INVARIANT1() public {
        // PASS
        assert_BASE_INVARIANT_B();
    }

    function test_TM_INVARIANT_B() public {
        // PASS
        _setUpBlockAndActor(23863, USER2);
        this.mintToActor(3, 2517);
        _setUpBlockAndActor(77040, USER1);
        this.enableController(115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _setUpBlockAndActor(115661, USER1);
        this.assert_BM_INVARIANT_G();
        echidna_TM_INVARIANT();
    }

    function test_TM_INVARIANT_A2() public {
        // PASS
        _setUpBlockAndActor(24293, USER1);
        this.depositToActor(464, 95416406916653671687163906321353417359071456765389709042486010813678577176823);
        _setUpBlockAndActor(47163, USER2);
        this.enableController(115792089237316195423570889601861022891927484329094684320502060868636724166656);
        _setUpBlockAndActor(47163, USER2);
        this.assert_BM_INVARIANT_G();
        echidna_TM_INVARIANT();
    }

    function test_TM_INVARIANT_B2() public {
        // PASS
        _setUpBlockAndActor(31532, USER3);
        this.mintToActor(134, 38950093316855029701707435728471143612397649181229202547446285813971152397387);
        _setUpBlockAndActor(31532, USER2);
        this.repayWithShares(129, 208);
        echidna_TM_INVARIANT();
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                 BROKEN INVARIANTS REVISION 2                              //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function test_BASE_INVARIANT2() public {
        // PASS
        _setUpBlockAndActor(25742, USER3);
        this.mintToActor(
            457584007913129639927, 115792089237316195423570985008687907853269984665640564039457584007913129639768
        );
        echidna_BASE_INVARIANT();
    }

    function test_LM_INVARIANT_B() public {
        // PASS
        _setUpBlockAndActor(24253, USER3);
        this.setDebtSocialization(false);
        this.mintToActor(40, 115792089237316195423570985008687907853269984665640564039457584007911240072655);
    }

    function test_BM_INVARIANT6() public {
        // PASS
        this.enableController(468322383632155574862945881956174631649161871295786712111360326257);
        this.setPrice(726828870758264026864714326152620643619927705875320304690180955674, 11);
        this.enableCollateral(15111);
        this.setLTV(3456147621700665956033923462455625826034483547574136595412029999975872, 1, 1, 0);
        this.depositToActor(1, 0);
        this.borrowTo(1, 304818507942225219676445155333052560942359548832832651640621508);
        echidna_BM_INVARIANT();
    }

    function test_echidna_VM_INVARIANT_C1() public {
        vm.skip(true);
        this.setLTV(161537350060562470698068789285938700031433026666990925968846691117425, 1, 1, 0);
        this.mintToActor(2, 0);
        this.setPrice(15141093523755052381928072114906306924899029026721034293540167406168436, 12);
        this.enableController(0);

        console.log("TotalSupply: ", eTST.totalSupply());
        console.log("TotalAssets: ", eTST.totalAssets());

        this.enableCollateral(4565920164825741688803703057878134831253824142353322861254361347742);
        this.borrowTo(1, 0);

        console.log("TotalSupply: ", eTST.totalSupply());
        console.log("TotalAssets: ", eTST.totalAssets());

        console.log("balanceOf: ", eTST.balanceOf(address(actor)));
        console.log("debtOf: ", eTST.debtOf(address(actor)));

        _delay(525);

        console.log("----------");

        console.log("TotalSupply: ", eTST.totalSupply());
        console.log("TotalAssets: ", eTST.totalAssets());

        console.log("balanceOf: ", eTST.balanceOf(address(actor)));
        console.log("debtOf: ", eTST.debtOf(address(actor)));

        console.log("----------");

        this.repayWithShares(2, 0);

        console.log("----------");

        console.log("balanceOf: ", eTST.balanceOf(address(actor)));
        console.log("debtOf: ", eTST.debtOf(address(actor)));

        console.log("TotalSupply: ", eTST.totalSupply());
        console.log("TotalAssets: ", eTST.totalAssets());

        console.log("----------");

        /*         this.loop(2,0);

        console.log("----------");

        console.log("balanceOf: ", eTST.balanceOf(address(actor)));
        console.log("debtOf: ", eTST.debtOf(address(actor)));

        console.log("TotalSupply: ", eTST.totalSupply());
        console.log("TotalAssets: ", eTST.totalAssets());

        console.log("----------");

        this.repayWithShares(3,0);

        console.log("----------");

        console.log("balanceOf: ", eTST.balanceOf(address(actor)));
        console.log("debtOf: ", eTST.debtOf(address(actor)));

        console.log("TotalSupply: ", eTST.totalSupply());
        console.log("TotalAssets: ", eTST.totalAssets());

        console.log("----------"); */

        assert_VM_INVARIANT_C();
    }

    function test_liquidate_bug() public {
        _setUpActorAndDelay(USER3, 297507);
        this.setLTV(115792089237316195423570985008687907853269984665640564039457584007913129639935, 433, 433, 0);
        _setUpActor(USER1);
        this.enableController(1524785991);
        _setUpActorAndDelay(USER1, 439556);
        this.enableCollateral(217905055956562793374063556811130300111285293815122069343455239377127312);
        _setUpActorAndDelay(USER3, 566039);
        this.enableCollateral(29);
        _setUpActorAndDelay(USER3, 209930);
        this.enableController(1524785993);
        _delay(271957);
        this.liquidate(2848675, 0, 512882652);
    }

    function test_VM_INVARIANT5() public {
        this.setLTV(22366818273602115439851901107761977982005180121616743889078085180117, 1, 1, 0);
        this.mintToActor(1, 0);
        this.enableCollateral(0);
        this.setPrice(167287376704962748125159831258059871163051958738722404000304447051, 11);
        this.enableController(0);
        this.borrowTo(1, 0);
        this.repayTo(1, 0);
    }

    function test_borrowing_coverage() public {
        this.enableController(0);
        this.borrowTo(
            115792089237316195423570985008687907853269984665640564039457584007913129639935,
            1210346675714198101847835018885699222114751859615
        );
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function _setUpBlockAndActor(uint256 _block, address _user) internal {
        vm.roll(_block);
        actor = actors[_user];
    }

    function _delay(uint256 _seconds) internal {
        vm.warp(block.timestamp + _seconds);
    }

    function _setUpActor(address _origin) internal {
        actor = actors[_origin];
    }

    function _setUpActorAndDelay(address _origin, uint256 _seconds) internal {
        actor = actors[_origin];
        vm.warp(block.timestamp + _seconds);
    }

    function _setUpTimestampAndActor(uint256 _timestamp, address _user) internal {
        vm.warp(_timestamp);
        actor = actors[_user];
    }
}
