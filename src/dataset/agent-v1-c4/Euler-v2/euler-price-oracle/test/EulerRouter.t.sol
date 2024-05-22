// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";
import {StubERC4626} from "test/StubERC4626.sol";
import {StubPriceOracle} from "test/adapter/StubPriceOracle.sol";
import {boundAddr, distinct} from "test/utils/TestUtils.sol";
import {IPriceOracle} from "src/interfaces/IPriceOracle.sol";
import {Errors} from "src/lib/Errors.sol";
import {EulerRouter} from "src/EulerRouter.sol";

contract EulerRouterTest is Test {
    address GOVERNOR = makeAddr("GOVERNOR");
    EulerRouter router;

    address WETH = makeAddr("WETH");
    address eWETH;
    address eeWETH;

    address DAI = makeAddr("DAI");
    address eDAI;
    address eeDAI;

    StubPriceOracle eOracle;

    function setUp() public {
        router = new EulerRouter(GOVERNOR);
    }

    function test_Constructor_Integrity() public view {
        assertEq(router.fallbackOracle(), address(0));
    }

    function test_Constructor_RevertsWhen_GovernorIsZeroAddress() public {
        vm.expectRevert(Errors.PriceOracle_InvalidConfiguration.selector);
        new EulerRouter(address(0));
    }

    function test_GovSetConfig_Integrity(address base, address quote, address oracle) public {
        vm.assume(base != quote);
        (address token0, address token1) = base < quote ? (base, quote) : (quote, base);
        vm.expectEmit();
        emit EulerRouter.ConfigSet(token0, token1, oracle);
        vm.prank(GOVERNOR);
        router.govSetConfig(base, quote, oracle);

        assertEq(router.getConfiguredOracle(base, quote), oracle);
        assertEq(router.getConfiguredOracle(quote, base), oracle);
    }

    function test_GovSetConfig_Integrity_OverwriteOk(address base, address quote, address oracleA, address oracleB)
        public
    {
        vm.assume(base != quote);
        (address token0, address token1) = base < quote ? (base, quote) : (quote, base);
        vm.expectEmit();
        emit EulerRouter.ConfigSet(token0, token1, oracleA);
        vm.prank(GOVERNOR);
        router.govSetConfig(base, quote, oracleA);

        vm.expectEmit();
        emit EulerRouter.ConfigSet(token0, token1, oracleB);
        vm.prank(GOVERNOR);
        router.govSetConfig(base, quote, oracleB);

        assertEq(router.getConfiguredOracle(base, quote), oracleB);
        assertEq(router.getConfiguredOracle(quote, base), oracleB);
    }

    function test_GovSetConfig_RevertsWhen_CallerNotGovernor(
        address caller,
        address base,
        address quote,
        address oracle
    ) public {
        vm.assume(base != quote);
        vm.assume(caller != GOVERNOR);

        vm.expectRevert(Errors.Governance_CallerNotGovernor.selector);
        vm.prank(caller);
        router.govSetConfig(base, quote, oracle);
    }

    function test_GovSetConfig_RevertsWhen_BaseEqQuote(address base, address oracle) public {
        vm.expectRevert(Errors.PriceOracle_InvalidConfiguration.selector);
        vm.prank(GOVERNOR);
        router.govSetConfig(base, base, oracle);
    }

    function test_GovSetVaultResolver_Integrity(address vault, address asset) public {
        vault = boundAddr(vault);
        vm.mockCall(vault, abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(asset));
        vm.expectEmit();
        emit EulerRouter.ResolvedVaultSet(vault, asset);

        vm.prank(GOVERNOR);
        router.govSetResolvedVault(vault, true);

        assertEq(router.resolvedVaults(vault), asset);
    }

    function test_GovSetVaultResolver_Integrity_OverwriteOk(address vault, address assetA, address assetB) public {
        vault = boundAddr(vault);
        vm.mockCall(vault, abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(assetA));
        vm.prank(GOVERNOR);
        router.govSetResolvedVault(vault, true);

        vm.mockCall(vault, abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(assetB));
        vm.prank(GOVERNOR);
        router.govSetResolvedVault(vault, true);

        assertEq(router.resolvedVaults(vault), assetB);
    }

    function test_GovSetVaultResolver_RevertsWhen_CallerNotGovernor(address caller, address vault) public {
        vm.assume(caller != GOVERNOR);

        vm.expectRevert(Errors.Governance_CallerNotGovernor.selector);
        vm.prank(caller);
        router.govSetResolvedVault(vault, true);
    }

    function test_GovSetFallbackOracle_Integrity(address fallbackOracle) public {
        vm.prank(GOVERNOR);
        router.govSetFallbackOracle(fallbackOracle);

        assertEq(router.fallbackOracle(), fallbackOracle);
    }

    function test_GovSetFallbackOracle_OverwriteOk(address fallbackOracleA, address fallbackOracleB) public {
        vm.prank(GOVERNOR);
        router.govSetFallbackOracle(fallbackOracleA);

        vm.prank(GOVERNOR);
        router.govSetFallbackOracle(fallbackOracleB);

        assertEq(router.fallbackOracle(), fallbackOracleB);
    }

    function test_GovSetFallbackOracle_ZeroOk() public {
        vm.prank(GOVERNOR);
        router.govSetFallbackOracle(address(0));

        assertEq(router.fallbackOracle(), address(0));
    }

    function test_GovSetFallbackOracle_RevertsWhen_CallerNotGovernor(address caller, address fallbackOracle) public {
        vm.assume(caller != GOVERNOR);

        vm.expectRevert(Errors.Governance_CallerNotGovernor.selector);
        vm.prank(caller);
        router.govSetFallbackOracle(fallbackOracle);
    }

    function test_Quote_Integrity_BaseEqQuote(uint256 inAmount, address base, address oracle) public view {
        base = boundAddr(base);
        oracle = boundAddr(oracle);
        vm.assume(base != oracle);
        inAmount = bound(inAmount, 1, type(uint128).max);

        uint256 outAmount = router.getQuote(inAmount, base, base);
        assertEq(outAmount, inAmount);
        (uint256 bidOutAmount, uint256 askOutAmount) = router.getQuotes(inAmount, base, base);
        assertEq(bidOutAmount, inAmount);
        assertEq(askOutAmount, inAmount);
    }

    function test_Quote_Integrity_HasOracle(
        uint256 inAmount,
        address base,
        address quote,
        address oracle,
        uint256 outAmount
    ) public {
        base = boundAddr(base);
        quote = boundAddr(quote);
        oracle = boundAddr(oracle);
        vm.assume(distinct(base, quote, oracle));
        inAmount = bound(inAmount, 1, type(uint128).max);

        vm.mockCall(
            oracle, abi.encodeWithSelector(IPriceOracle.getQuote.selector, inAmount, base, quote), abi.encode(outAmount)
        );
        vm.mockCall(
            oracle,
            abi.encodeWithSelector(IPriceOracle.getQuotes.selector, inAmount, base, quote),
            abi.encode(outAmount, outAmount)
        );
        vm.prank(GOVERNOR);
        router.govSetConfig(base, quote, oracle);

        uint256 _outAmount = router.getQuote(inAmount, base, quote);
        assertEq(_outAmount, outAmount);
        (uint256 bidOutAmount, uint256 askOutAmount) = router.getQuotes(inAmount, base, quote);
        assertEq(bidOutAmount, outAmount);
        assertEq(askOutAmount, outAmount);
    }

    function test_Quote_Integrity_BaseIsVault(
        uint256 inAmount,
        address baseAsset,
        address quote,
        uint256 rate1,
        uint256 rate2
    ) public {
        baseAsset = boundAddr(baseAsset);
        quote = boundAddr(quote);
        rate1 = bound(rate1, 1, 1e24);
        rate2 = bound(rate2, 1, 1e24);

        address oracle = address(new StubPriceOracle());
        address base = address(new StubERC4626(baseAsset, rate2));
        vm.assume(distinct(base, baseAsset, quote, oracle));

        vm.startPrank(GOVERNOR);
        StubPriceOracle(oracle).setPrice(baseAsset, quote, rate1);
        router.govSetConfig(baseAsset, quote, oracle);
        router.govSetResolvedVault(base, true);
        inAmount = bound(inAmount, 1, type(uint128).max);
        uint256 expectedOutAmount = (inAmount * rate2 / 1e18) * rate1 / 1e18;
        uint256 outAmount = router.getQuote(inAmount, base, quote);
        assertEq(outAmount, expectedOutAmount);
        (uint256 bidOutAmount, uint256 askOutAmount) = router.getQuotes(inAmount, base, quote);
        assertEq(bidOutAmount, expectedOutAmount);
        assertEq(askOutAmount, expectedOutAmount);
    }

    function test_GetQuote_Integrity_NoOracleButHasFallback(
        uint256 inAmount,
        address base,
        address quote,
        address fallbackOracle,
        uint256 outAmount
    ) public {
        base = boundAddr(base);
        quote = boundAddr(quote);
        fallbackOracle = boundAddr(fallbackOracle);
        vm.assume(distinct(base, quote, fallbackOracle));
        inAmount = bound(inAmount, 1, type(uint128).max);

        vm.prank(GOVERNOR);
        router.govSetFallbackOracle(fallbackOracle);

        vm.mockCall(
            fallbackOracle,
            abi.encodeWithSelector(IPriceOracle.getQuote.selector, inAmount, base, quote),
            abi.encode(outAmount)
        );
        vm.mockCall(
            fallbackOracle,
            abi.encodeWithSelector(IPriceOracle.getQuotes.selector, inAmount, base, quote),
            abi.encode(outAmount, outAmount)
        );
        uint256 _outAmount = router.getQuote(inAmount, base, quote);
        assertEq(_outAmount, outAmount);
        (uint256 bidOutAmount, uint256 askOutAmount) = router.getQuotes(inAmount, base, quote);
        assertEq(bidOutAmount, outAmount);
        assertEq(askOutAmount, outAmount);
    }

    function test_GetQuote_RevertsWhen_NoOracleNoFallback(uint256 inAmount, address base, address quote) public {
        base = boundAddr(base);
        quote = boundAddr(quote);
        vm.assume(base != quote);
        inAmount = bound(inAmount, 1, type(uint128).max);

        vm.expectRevert(abi.encodeWithSelector(Errors.PriceOracle_NotSupported.selector, base, quote));
        router.getQuote(inAmount, base, quote);
        vm.expectRevert(abi.encodeWithSelector(Errors.PriceOracle_NotSupported.selector, base, quote));
        router.getQuotes(inAmount, base, quote);
    }

    function test_ResolveOracle_BaseEqQuote(uint256 inAmount, address base) public view {
        (uint256 resolvedInAmount, address resolvedBase, address resolvedQuote, address resolvedOracle) =
            router.resolveOracle(inAmount, base, base);

        assertEq(resolvedInAmount, inAmount);
        assertEq(resolvedBase, base);
        assertEq(resolvedQuote, base);
        assertEq(resolvedOracle, address(0));
    }

    function test_ResolveOracle_HasOracle(uint256 inAmount, address base, address quote, address oracle) public {
        vm.assume(base != quote);
        vm.assume(oracle != address(0));
        vm.prank(GOVERNOR);
        router.govSetConfig(base, quote, oracle);

        (uint256 resolvedInAmount, address resolvedBase, address resolvedQuote, address resolvedOracle) =
            router.resolveOracle(inAmount, base, quote);
        assertEq(resolvedInAmount, inAmount);
        assertEq(resolvedBase, base);
        assertEq(resolvedQuote, quote);
        assertEq(resolvedOracle, oracle);
    }

    function test_ResolveOracle_BaseIsVault(
        uint256 inAmount,
        address baseAsset,
        address quote,
        uint256 rate1,
        uint256 rate2
    ) public {
        baseAsset = boundAddr(baseAsset);
        quote = boundAddr(quote);
        rate1 = bound(rate1, 1, 1e24);
        rate2 = bound(rate2, 1, 1e24);

        address oracle = address(new StubPriceOracle());
        address base = address(new StubERC4626(baseAsset, rate2));
        vm.assume(distinct(base, baseAsset, quote, oracle));

        vm.startPrank(GOVERNOR);
        StubPriceOracle(oracle).setPrice(baseAsset, quote, rate1);
        router.govSetConfig(baseAsset, quote, oracle);
        router.govSetResolvedVault(base, true);
        inAmount = bound(inAmount, 1, type(uint128).max);

        (, address resolvedBase, address resolvedQuote, address resolvedOracle) =
            router.resolveOracle(inAmount, base, quote);
        assertEq(resolvedBase, baseAsset);
        assertEq(resolvedQuote, quote);
        assertEq(resolvedOracle, oracle);
    }

    function test_ResolveOracle_BaseIsVaultWithAssetEqQuote(uint256 inAmount, address baseAsset, uint256 rate1)
        public
    {
        baseAsset = boundAddr(baseAsset);
        rate1 = bound(rate1, 1, 1e24);

        address oracle = address(new StubPriceOracle());
        address base = address(new StubERC4626(baseAsset, rate1));
        vm.assume(distinct(base, baseAsset, oracle));

        vm.startPrank(GOVERNOR);
        router.govSetResolvedVault(base, true);
        inAmount = bound(inAmount, 1, type(uint128).max);

        (, address resolvedBase, address resolvedQuote, address resolvedOracle) =
            router.resolveOracle(inAmount, base, baseAsset);
        assertEq(resolvedBase, baseAsset);
        assertEq(resolvedQuote, baseAsset);
        assertEq(resolvedOracle, address(0));
    }

    function test_ResolveOracle_HasOracleInverse(uint256 inAmount, address base, address quote, address oracle)
        public
    {
        vm.assume(base != quote);
        vm.assume(oracle != address(0));
        vm.prank(GOVERNOR);
        router.govSetConfig(base, quote, oracle);

        (uint256 resolvedInAmount, address resolvedBase, address resolvedQuote, address resolvedOracle) =
            router.resolveOracle(inAmount, base, quote);
        assertEq(resolvedInAmount, inAmount);
        assertEq(resolvedBase, base);
        assertEq(resolvedQuote, quote);
        assertEq(resolvedOracle, oracle);
    }

    function test_ResolveOracle_NoOracleButHasFallback(uint256 inAmount, address base, address quote, address oracle)
        public
    {
        vm.assume(base != quote);
        vm.assume(oracle != address(0));
        vm.prank(GOVERNOR);
        router.govSetFallbackOracle(oracle);

        (uint256 resolvedInAmount, address resolvedBase, address resolvedQuote, address resolvedOracle) =
            router.resolveOracle(inAmount, base, quote);
        assertEq(resolvedInAmount, inAmount);
        assertEq(resolvedBase, base);
        assertEq(resolvedQuote, quote);
        assertEq(resolvedOracle, oracle);
    }

    function test_ResolveOracle_NoOracleNoFallback(uint256 inAmount, address base, address quote) public {
        vm.assume(base != quote);
        vm.expectRevert(abi.encodeWithSelector(Errors.PriceOracle_NotSupported.selector, base, quote));
        router.resolveOracle(inAmount, base, quote);
    }

    function test_TransferGovernance_RevertsWhen_CallerNotGovernor(address caller, address newGovernor) public {
        vm.assume(caller != GOVERNOR);
        vm.expectRevert(Errors.Governance_CallerNotGovernor.selector);
        vm.prank(caller);
        router.transferGovernance(newGovernor);
    }

    function test_TransferGovernance_Integrity(address newGovernor) public {
        vm.assume(newGovernor != address(0));
        vm.prank(GOVERNOR);
        router.transferGovernance(newGovernor);

        assertEq(router.governor(), newGovernor);
    }

    function test_TransferGovernance_Integrity_ZeroAddress() public {
        vm.prank(GOVERNOR);
        router.transferGovernance(address(0));

        assertEq(router.governor(), address(0));
    }
}
