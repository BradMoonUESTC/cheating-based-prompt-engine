// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {StorageSlot} from "./StorageSlot.sol";
import {ValidationLogic} from "./ValidationLogic.sol";

import {DataTypes} from "../types/DataTypes.sol";
import {Errors} from "../helpers/Errors.sol";

import {ICertiNft} from "../../interfaces/ICertiNft.sol";
import {INToken} from "../../interfaces/INToken.sol";

library NftLogic {
    function mintCNft(
        address _cNft,
        address _to,
        uint256 _tokenId,
        uint256 _ltv
    ) internal {
        ValidationLogic.validateManager();
        ICertiNft(_cNft).mint(_to, _tokenId, _ltv);
    }

    function burnCNft(address _cNft, uint256 _tokenId) internal {
        ValidationLogic.validateManager();
        ICertiNft(_cNft).burn(_tokenId);
    }

    function mintNToken(address _nToken, uint256 _amount) internal {
        ValidationLogic.validateManager();
        INToken(_nToken).mint(address(this), _amount);
    }

    function burnNToken(address _nToken, uint256 _amount) internal {
        ValidationLogic.validateManager();
        INToken(_nToken).burn(address(this), _amount);
    }

    function addNftToUser(
        address _user,
        address _nft,
        uint256 _tokenId
    ) internal {
        ValidationLogic.validateManager();
        DataTypes.NftStorage storage ns = StorageSlot.getVaultNftStorage();
        uint256 length = ns.nftUsers.length;
        bool userExist;
        for (uint256 i = 0; i < length; i++) {
            if (ns.nftUsers[i] == _user) {
                userExist = true;
                break;
            }
        }
        if (!userExist) {
            ns.nftUsers.push(_user);
        }
        bool tokenExist;
        DataTypes.NftStatus[] storage status = ns.nftStatus[_user][_nft];
        for (uint256 i = 0; i < status.length; i++) {
            if (status[i].tokenId == _tokenId) {
                tokenExist = true;
                break;
            }
        }
        if (!tokenExist) {
            DataTypes.NftStatus memory currentNftStatus = DataTypes.NftStatus({
                isRefinanced: false,
                tokenId: _tokenId
            });
            status.push(currentNftStatus);
        }
    }

    function removeNftFromUser(
        address _user,
        address _nft,
        uint256 _tokenId
    ) internal {
        ValidationLogic.validateManager();
        DataTypes.NftStorage storage ns = StorageSlot.getVaultNftStorage();
        uint256 length = ns.nftUsers.length;
        bool userExist;
        for (uint256 i = 0; i < length; i++) {
            if (ns.nftUsers[i] == _user) {
                userExist = true;
                break;
            }
        }
        require(userExist, Errors.VAULT_NFT_USER_NOT_EXIST);
        bool tokenExist;
        DataTypes.NftStatus[] storage status = ns.nftStatus[_user][_nft];
        for (uint256 i = 0; i < status.length; i++) {
            if (status[i].tokenId == _tokenId) {
                tokenExist = true;
                status[i] = status[status.length - 1];
                status.pop();
                break;
            }
        }
        require(tokenExist, Errors.VAULT_NFT_NOT_EXIST);
    }

    function isNftDepsoitedForUser(
        address _user,
        address _nft,
        uint256 _tokenId
    ) internal view returns (bool) {
        DataTypes.NftStorage storage ns = StorageSlot.getVaultNftStorage();
        DataTypes.NftStatus[] storage status = ns.nftStatus[_user][_nft];
        for (uint256 i = 0; i < status.length; i++) {
            if (status[i].tokenId == _tokenId) {
                if (!status[i].isRefinanced) {
                    return true;
                }
            }
        }
        return false;
    }

    function updateNftRefinanceStatus(
        address _user,
        address _nft,
        uint256 _tokenId
    ) internal {
        DataTypes.AddressStorage storage addrs = StorageSlot
            .getVaultAddressStorage();
        require(addrs.refinance == msg.sender, Errors.INVALID_CALLER);
        DataTypes.NftStorage storage ns = StorageSlot.getVaultNftStorage();
        DataTypes.NftStatus[] storage status = ns.nftStatus[_user][_nft];
        for (uint256 i = 0; i < status.length; i++) {
            if (status[i].tokenId == _tokenId) {
                status[i].isRefinanced = true;
            }
        }
    }

    function getNftDepositLtv(
        address _nft,
        uint256 _tokenId
    ) internal view returns (uint256) {
        DataTypes.NftStorage storage ns = StorageSlot.getVaultNftStorage();
        ICertiNft certiNft = ICertiNft(ns.nftInfos[_nft].certiNft);
        return certiNft.tokenLtv(_tokenId);
    }
}
