// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

/**
 * @title MintableERC721
 * @dev ERC721 minting logic
 */
contract MintableERC721 is ERC721Enumerable, Ownable {
    string public baseURI;
    mapping(address => uint256) public mintCounts;
    address public faucet;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
        baseURI = "https://MintableERC721/";
    }

    /**
     * @dev Function to mint tokens
     * @param tokenId The id of tokens to mint.
     * @return A boolean that indicates if the operation was successful.
     */
    function mint(uint256 tokenId) public returns (bool) {
        if (faucet == address(0)) {
            require(
                (mintCounts[_msgSender()] + 1) <= 10,
                "MintableERC721: exceed mint limit"
            );
        } else {
            require(
                faucet == _msgSender(),
                "MintableERC721: minting not allowed"
            );
        }

        require(tokenId < 10000, "MintableERC721: exceed max token id");

        mintCounts[_msgSender()] += 1;

        _mint(_msgSender(), tokenId);
        return true;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory baseURI_) public onlyOwner {
        baseURI = baseURI_;
    }

    function setFaucet(address faucet_) public onlyOwner {
        faucet = faucet_;
    }
}
