// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface INftPool {
    event NftDeposited(
        address indexed nft,
        uint256[] tokenIds,
        address indexed owner
    );

    event NftWithdrawn(
        address indexed nft,
        uint256[] tokenIds,
        address indexed owner
    );

    event NftRefinance(
        address indexed nft,
        uint256 tokenId,
        address indexed owner,
        uint256 amount,
        address indexed reserve
    );

    function deposit(
        address[] calldata _nfts,
        uint256[][] calldata _tokenIds
    ) external payable;

    function withdraw(
        address _user,
        address[] calldata _nfts,
        uint256[][] calldata _tokenIds
    ) external;

    function refinance(
        address[] calldata _user,
        address[] calldata _nfts,
        uint256[] calldata _tokenIds
    ) external;

    function swapRefinancedETH() external payable;

    function repayETH(
        address[] memory _nftAssets,
        uint256[] memory _nftTokenIds,
        uint256[] memory _amounts,
        bool[] memory _toDeposit
    ) external payable;

    function getTokenStatus(
        address _user,
        address _nft,
        uint256 _tokenId
    ) external view returns (bool, bool);

    function getNftDebtData(
        address[] memory nftAssets,
        uint256[] memory nftTokenIds
    ) external view returns (uint256[] memory);
}
