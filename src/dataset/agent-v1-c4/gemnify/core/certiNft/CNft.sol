// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {ERC721EnumerableUpgradeable, ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

import {IERC721MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721MetadataUpgradeable.sol";
import {IERC721ReceiverUpgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC721ReceiverUpgradeable.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";

import {ICertiNft} from "../interfaces/ICertiNft.sol";

abstract contract CNft is
    ICertiNft,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC721EnumerableUpgradeable
{
    IERC721MetadataUpgradeable private nft;

    string private _customBaseURI;

    mapping(address => bool) private authorized;

    mapping(uint256 => uint256) public ltv;

    modifier onlyAuthorized() {
        require(authorized[msg.sender], "CNft: caller is not authorized");
        _;
    }

    function __CNft_init(
        IERC721MetadataUpgradeable _nft,
        string memory _name,
        string memory _symbol
    ) internal onlyInitializing {
        __Ownable_init();
        __ReentrancyGuard_init();
        __ERC721_init(_name, _symbol);
        __ERC721Enumerable_init();

        nft = _nft;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external view override returns (bytes4) {
        require(msg.sender == address(nft), "CNft: nft not acceptable");
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }

    function mint(
        address _to,
        uint256 _tokenId,
        uint256 _ltv
    ) external override nonReentrant onlyAuthorized {
        ltv[_tokenId] = _ltv;
        _mint(_to, _tokenId);
    }

    function burn(
        uint256 _tokenId
    ) external override nonReentrant onlyAuthorized {
        _burn(_tokenId);
    }

    function authorise(address _addr, bool _authorized) external onlyOwner {
        authorized[_addr] = _authorized;
    }

    function underlyingAsset() external view override returns (address) {
        return address(nft);
    }

    function setBaseURI(string memory baseURI_) public onlyOwner {
        _customBaseURI = baseURI_;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _customBaseURI;
    }

    function tokenURI(
        uint256 _tokenId
    )
        public
        view
        override(ERC721Upgradeable, IERC721MetadataUpgradeable)
        returns (string memory)
    {
        if (bytes(_customBaseURI).length > 0) {
            return super.tokenURI(_tokenId);
        }

        return nft.tokenURI(_tokenId);
    }

    function tokenLtv(
        uint256 _tokenId
    ) external view override returns (uint256) {
        return ltv[_tokenId];
    }

    function approve(
        address to,
        uint256 tokenId
    ) public virtual override(ERC721Upgradeable, IERC721Upgradeable) {
        to;
        tokenId;
        revert("APPROVAL_NOT_SUPPORTED");
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) public virtual override(ERC721Upgradeable, IERC721Upgradeable) {
        operator;
        approved;
        revert("APPROVAL_NOT_SUPPORTED");
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override(ERC721Upgradeable, IERC721Upgradeable) {
        from;
        to;
        tokenId;
        revert("TRANSFER_NOT_SUPPORTED");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override(ERC721Upgradeable, IERC721Upgradeable) {
        from;
        to;
        tokenId;
        revert("TRANSFER_NOT_SUPPORTED");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public virtual override(ERC721Upgradeable, IERC721Upgradeable) {
        from;
        to;
        tokenId;
        _data;
        revert("TRANSFER_NOT_SUPPORTED");
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721Upgradeable) {
        from;
        to;
        tokenId;
        revert("TRANSFER_NOT_SUPPORTED");
    }
}
