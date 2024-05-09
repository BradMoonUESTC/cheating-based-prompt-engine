//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IWETH {
  function balanceOf(address account) external view returns (uint256);

  function deposit() external payable;

  function withdraw(uint256) external;

  function approve(address guy, uint256 wad) external returns (bool);

  function transferFrom(address src, address dst, uint256 wad) external returns (bool);
}
