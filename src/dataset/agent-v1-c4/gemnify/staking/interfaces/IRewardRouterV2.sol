// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IRewardRouterV2 {
    function mintAndStakeUlpNFT(
        address _user,
        address _nft,
        uint256 _tokenId,
        uint256 _minEthg,
        uint256 _minUlp
    ) external returns (uint256);

    function feeUlpTracker() external view returns (address);
}
