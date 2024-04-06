// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import {ERC721} from "solmate/tokens/ERC721.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {PanopticPool} from "@contracts/PanopticPool.sol";

/// @title Reward NFT for `PanopticFactory` donors/deployers.
/// @notice Currently a placeholder, token standard/metadata subject to change.
contract DonorNFT is Owned, ERC721 {
    address internal panopticFactory;

    uint256 internal nextId;

    constructor() Owned(msg.sender) ERC721("", "") {}

    function changeFactory(address newFactory) external onlyOwner {
        panopticFactory = newFactory;
    }

    function tokenURI(uint256) public view override returns (string memory) {}

    /// @notice Called to issue reward NFT to the deployer of a new `PanopticPool` through `PanopticFactory`.
    /// @param deployer The address that deployed `newPoolContract` and donated funds for full-range liquidity
    function issueNFT(address deployer, PanopticPool, address, address, uint24) external {
        require(msg.sender == panopticFactory);

        _mint(deployer, nextId);
        nextId++;
    }
}
