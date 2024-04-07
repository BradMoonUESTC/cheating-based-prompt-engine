// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../libraries/BoringOwnableUpgradeable.sol";
import "../../../../interfaces/HMX/IHMXCalculator.sol";

contract HLPPricingHelper is BoringOwnableUpgradeable, UUPSUpgradeable {
    address public immutable hmxCalculator;
    address public immutable hlp;

    constructor(address _hmxCalculator, address _hlp) {
        hmxCalculator = _hmxCalculator;
        hlp = _hlp;
    }

    function initialize() external initializer {
        __BoringOwnable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function getPrice() external view returns (uint256) {
        uint256 aum = IHMXCalculator(hmxCalculator).getAUME30(true);
        uint256 supply = IERC20(hlp).totalSupply();
        return (aum * 1e6) / supply;
    }
}
