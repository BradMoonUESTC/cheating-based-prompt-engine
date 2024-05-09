// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IERC721MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC721MetadataUpgradeable.sol";
import {IERC721ReceiverUpgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC721ReceiverUpgradeable.sol";
import {IERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC721EnumerableUpgradeable.sol";

interface ICertiNft is
    IERC721MetadataUpgradeable,
    IERC721ReceiverUpgradeable,
    IERC721EnumerableUpgradeable
{
    function mint(address to, uint256 tokenId, uint256 ltv) external;

    function burn(uint256 tokenId) external;

    function underlyingAsset() external view returns (address);

    function tokenLtv(uint256 _tokenId) external view returns (uint256);
}
