// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../../../../src/EVault/shared/AssetTransfers.sol";
import "../../../../src/EVault/shared/Errors.sol";

import "../EVaultTestBase.t.sol";

contract AssetTransfersHarness is AssetTransfers {
    constructor() Base(Integrations(addressWithCode(), addressWithCode(), addressWithCode(), address(0), address(0))) {}

    function exposed_pullAssets(VaultCache memory cache, address from, Assets amount) external {
        pullAssets(cache, from, amount);
    }

    function addressWithCode() internal returns (address) {
        return address(new Errors());
    }
}

contract AssetTransfersTest is EVaultTestBase {
    using TypesLib for uint256;

    AssetTransfersHarness tc; // tested contract
    address from;

    function setUp() public override {
        super.setUp();

        tc = new AssetTransfersHarness();
        from = makeAddr("depositor");
        assetTST.mint(from, type(uint256).max);
        hoax(from);
        assetTST.approve(address(tc), type(uint256).max);
    }

    function testFuzz_pullAssets(uint256 cash, uint256 amount) public {
        cash = bound(cash, 0, MAX_SANE_AMOUNT);
        amount = bound(amount, 0, MAX_SANE_AMOUNT);
        vm.assume(cash + amount < MAX_SANE_AMOUNT);
        VaultCache memory cache = initCache();

        cache.cash = cash.toAssets();
        assetTST.setBalance(address(tc), cash);

        Assets assets = amount.toAssets();

        tc.exposed_pullAssets(cache, from, assets);
        uint256 cashAfter = assetTST.balanceOf(address(tc));
        Assets transferred = (cashAfter - cash).toAssets();

        assertEq(transferred, assets);
        assertEq(transferred.toUint(), assetTST.balanceOf(address(tc)) - cash);
    }

    function test_pullAssets_zeroIsNoop() public {
        VaultCache memory cache = initCache();

        tc.exposed_pullAssets(cache, from, Assets.wrap(0));
        uint256 cashAfter = assetTST.balanceOf(address(tc));
        Assets transferred = cashAfter.toAssets();

        assertEq(transferred, ZERO_ASSETS);
        assertEq(assetTST.balanceOf(address(tc)), 0);
    }

    function test_pullAssets_deflationaryTransfer() public {
        VaultCache memory cache = initCache();

        assetTST.configure("transfer/deflationary", abi.encode(0.5e18));

        tc.exposed_pullAssets(cache, from, Assets.wrap(1e18));
        uint256 cashAfter = assetTST.balanceOf(address(tc));
        Assets transferred = cashAfter.toAssets();

        assertEq(transferred, Assets.wrap(0.5e18));
        assertEq(assetTST.balanceOf(address(tc)), 0.5e18);
    }

    function test_pullAssets_inflationaryTransfer() public {
        VaultCache memory cache = initCache();

        assetTST.configure("transfer/inflationary", abi.encode(0.5e18));

        tc.exposed_pullAssets(cache, from, Assets.wrap(1e18));
        uint256 cashAfter = assetTST.balanceOf(address(tc));
        Assets transferred = cashAfter.toAssets();

        assertEq(transferred, Assets.wrap(1.5e18));
        assertEq(assetTST.balanceOf(address(tc)), 1.5e18);
    }

    function test_RevertWhenCashAfterOverflows_pullAssets() public {
        VaultCache memory cache = initCache();

        cache.cash = MAX_ASSETS;
        assetTST.setBalance(address(tc), MAX_ASSETS.toUint());

        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        tc.exposed_pullAssets(cache, from, Assets.wrap(1));

        cache.cash = Assets.wrap(1);
        assetTST.setBalance(address(tc), 1);

        vm.expectRevert(Errors.E_AmountTooLargeToEncode.selector);
        tc.exposed_pullAssets(cache, from, MAX_ASSETS);
    }

    function initCache() internal view returns (VaultCache memory cache) {
        cache.asset = IERC20(address(assetTST));
    }
}
