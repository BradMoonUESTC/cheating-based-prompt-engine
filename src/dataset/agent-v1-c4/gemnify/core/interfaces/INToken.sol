// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface INToken {
    function initialize(
        string calldata _name,
        string calldata _symbol,
        address _underlyingAsset
    ) external;

    function mint(address account, uint256 amount) external;

    function burn(address account, uint256 amount) external;

    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
}
