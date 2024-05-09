// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "./IVault.sol";

interface IUlpManager {
    function ulp() external view returns (address);

    function ethg() external view returns (address);

    function vault() external view returns (IVault);

    function cooldownDuration() external returns (uint256);

    function getPrice(bool _maximise) external view returns (uint256);

    function getAum(bool maximise) external view returns (uint256);

    function getAumInEthg(bool maximise) external view returns (uint256);

    function lastAddedAt(address _account) external returns (uint256);

    function addLiquidity(
        address _token,
        uint256 _amount,
        uint256 _minEthg,
        uint256 _minUlp
    ) external returns (uint256);

    function addLiquidityForAccount(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount,
        uint256 _minEthg,
        uint256 _minUlp
    ) external returns (uint256);

    function addLiquidityNFTForAccount(
        address _fundingAccount,
        address _account,
        address _nft,
        uint256 _tokenId,
        uint256 _minEthg,
        uint256 _minUlp
    ) external returns (uint256);

    function removeLiquidity(
        address _tokenOut,
        uint256 _ulpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);

    function removeLiquidityForAccount(
        address _account,
        address _tokenOut,
        uint256 _ulpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);

    function setShortsTrackerAveragePriceWeight(
        uint256 _shortsTrackerAveragePriceWeight
    ) external;

    function setCooldownDuration(uint256 _cooldownDuration) external;

    function removeLiquidityNFTForAccount(
        address _account,
        address _nft,
        uint256 _tokenId,
        address _weth,
        uint256 _ethAmount,
        uint256 _ulpAmount,
        address _receiver
    ) external returns (uint256);

    function getULPAmountWhenRedeemNft(
        address _nft,
        uint256 _tokenId,
        uint256 _ethAmount
    ) external view returns (uint256);

    function isNftDepsoitedForUser(
        address _user,
        address _nft,
        uint256 _tokenId
    ) external view returns (bool);
}
