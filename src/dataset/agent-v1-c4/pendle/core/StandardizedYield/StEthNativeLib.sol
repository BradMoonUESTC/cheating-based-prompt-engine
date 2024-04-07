// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../interfaces/IStETH.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library StETHNativeLib {
    address internal constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    function _depositStETH(uint256 amountNative) internal returns (uint256 amountStETHOut) {
        uint256 preBal = IERC20(STETH).balanceOf(address(this));
        IStETH(STETH).submit{value: amountNative}(address(0));
        return IERC20(STETH).balanceOf(address(this)) - preBal;
    }
}
