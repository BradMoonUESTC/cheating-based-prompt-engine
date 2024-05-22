// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../../src/EVault/IEVault.sol";

contract MockPriceOracle {
    error PO_BaseUnsupported();
    error PO_QuoteUnsupported();
    error PO_Overflow();
    error PO_NoPath();

    mapping(address base => mapping(address quote => uint256)) price;
    mapping(address base => mapping(address quote => Prices)) prices;

    struct Prices {
        bool set;
        uint256 bid;
        uint256 ask;
    }

    function name() external pure returns (string memory) {
        return "MockPriceOracle";
    }

    function getQuote(uint256 amount, address base, address quote) public view returns (uint256 out) {
        return calculateQuote(base, amount, price[resolveUnderlying(base)][quote]);
    }

    function getQuotes(uint256 amount, address base, address quote)
        external
        view
        returns (uint256 bidOut, uint256 askOut)
    {
        if (prices[resolveUnderlying(base)][quote].set) {
            return (
                calculateQuote(base, amount, prices[resolveUnderlying(base)][quote].bid),
                calculateQuote(base, amount, prices[resolveUnderlying(base)][quote].ask)
            );
        }

        bidOut = askOut = getQuote(amount, base, quote);
    }

    ///// Mock functions

    function setPrice(address base, address quote, uint256 newPrice) external {
        price[resolveUnderlying(base)][quote] = newPrice;
    }

    function setPrices(address base, address quote, uint256 newBid, uint256 newAsk) external {
        prices[resolveUnderlying(base)][quote] = Prices({set: true, bid: newBid, ask: newAsk});
    }

    function calculateQuote(address base, uint256 amount, uint256 p) internal view returns (uint256) {
        (bool success,) = base.staticcall(abi.encodeCall(IERC4626.asset, ()));
        if (base.code.length > 0 && success) amount = IEVault(base).convertToAssets(amount);

        return amount * p / 1e18;
    }

    function resolveUnderlying(address asset) internal view returns (address) {
        if (asset.code.length > 0) {
            (bool success, bytes memory data) = asset.staticcall(abi.encodeCall(IERC4626.asset, ()));
            if (success) return abi.decode(data, (address));
        }

        return asset;
    }
}
