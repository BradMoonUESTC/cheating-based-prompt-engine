// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface ICrossChain {
    enum FunctionType {
        DEPOSIT,
        WITHDRAW,
        REFINANCE
    }

    struct RefinanceNft {
        address user;
        address nft;
        uint256 tokenId;
    }

    function sendDepositNftMsg(
        address payable _user,
        address[] calldata _nfts,
        uint256[][] calldata _tokenIds
    ) external payable;

    function sendWithDrawNftMsg(
        address payable _user,
        address[] calldata _nfts,
        uint256[][] calldata _tokenIds
    ) external payable;

    function sendRefinanceNftMsg(
        address[] calldata _users,
        address[] calldata _nfts,
        uint256[] calldata _tokenIds,
        address payable _refundAddress
    ) external payable;

    function swapETH(
        address payable _refundAddress,
        address _toAddress,
        uint256 _swapValue
    ) external payable;

    function estimateSwapFee(
        address toAddress
    ) external view returns (uint256);

    function estimateDepositFee(
        address _user,
        address[] calldata _nfts,
        uint256[][] calldata _tokenIds
    ) external view returns (uint256);

    function estimateWithdrawFee(
        address _user,
        address[] calldata _nfts,
        uint256[][] calldata _tokenIds
    ) external view returns (uint256);

    function estimateRefinanceFee(
        address[] calldata _users,
        address[] calldata _nfts,
        uint256[] calldata _tokenIds
    ) external view returns (uint256);
}
