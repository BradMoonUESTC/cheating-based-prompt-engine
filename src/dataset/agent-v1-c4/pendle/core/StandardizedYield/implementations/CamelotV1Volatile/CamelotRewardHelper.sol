// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../../../libraries/TokenHelper.sol";
import "../../../../interfaces/Camelot/ICamelotNFTFactory.sol";
import "../../../../interfaces/Camelot/ICamelotNitroPoolFactory.sol";
import "../../../../interfaces/Camelot/ICamelotNFTPool.sol";
import "../../../../interfaces/Camelot/ICamelotNitroPool.sol";
import "../../../../interfaces/Camelot/ICamelotNFTHandler.sol";
import "../../../../interfaces/Camelot/ICamelotYieldBooster.sol";
import "../../../../interfaces/Camelot/IXGrail.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @dev This contract should leave at least MINIMUM_LIQUIDITY in NftPool position
 * to protect the position from being destroyed
 *
 * The reason for this is that once the position is destroyed, the de-allocation of xGrail
 * will be forced to occur and take away fees from our xGRAIL boosting
 */
contract CamelotRewardHelper is TokenHelper, ICamelotNFTHandler {
    ICamelotNitroPoolFactory internal constant NITRO_POOL_FACTORY =
        ICamelotNitroPoolFactory(0xe0a6b372Ac6AF4B37c7F3a989Fe5d5b194c24569);
    uint256 internal constant POSITION_UNINITIALIZED = type(uint256).max;
    uint256 internal constant MINIMUM_LIQUIDITY = 10 ** 3;
    bytes4 internal constant _ERC721_RECEIVED = 0x150b7a02;

    address public nitroPool;
    address public immutable nftPool;
    address public immutable GRAIL;
    address public immutable xGRAIL;
    uint256 public positionId = POSITION_UNINITIALIZED;

    address public yieldBooster;

    error InvalidTokenId(uint256 tokenId, uint256 positionId);

    modifier ensureValidTokenId(uint256 tokenId) {
        // Not allow receiving NFT from unwanted sources
        if (tokenId != positionId) {
            revert InvalidTokenId(tokenId, positionId);
        }
        _;
    }

    constructor(address _nftPool, uint256 _nitroPoolIndex) {
        nftPool = _nftPool;
        if (_nitroPoolIndex != type(uint256).max) {
            nitroPool = NITRO_POOL_FACTORY.getNitroPool(_nitroPoolIndex);
            require(ICamelotNitroPool(nitroPool).nftPool() == nftPool);
        }

        address lp;
        (lp, GRAIL, xGRAIL, , , , , ) = ICamelotNFTPool(nftPool).getPoolInfo();
        yieldBooster = ICamelotNFTPool(nftPool).yieldBooster();

        _safeApproveInf(lp, nftPool);
        IXGrail(xGRAIL).approveUsage(yieldBooster, type(uint256).max);
    }

    /**
     * @dev Though xGRAIL can be vested into GRAIL through vesting, it's not possible
     * to distribute this reward fairly on-chain.
     *
     * We decided to go with the second option (keep allocating xGRAIL to boost APR)
     */
    function _allocateXGrail() internal {
        if (_ensureYieldBoosterMatched()) return;

        uint256 amount = _selfBalance(xGRAIL);
        if (amount == 0) return;

        // there should be no reward without minimum liquidity minted
        assert(positionId != POSITION_UNINITIALIZED);

        IXGrail(xGRAIL).allocate(yieldBooster, amount, _getAllocationData());
    }

    function _ensureYieldBoosterMatched() private returns (bool yieldBoosterUpdated) {
        address oldYieldBooster = yieldBooster;
        address newYieldBooster = ICamelotNFTPool(nftPool).yieldBooster();

        if (oldYieldBooster == newYieldBooster) return false;

        // Avoid reverts from camelot's check for amount > 0
        uint256 amountAllocated = IXGrail(xGRAIL).usageAllocations(address(this), oldYieldBooster);
        if (amountAllocated > 0) {
            ICamelotYieldBooster(oldYieldBooster).forceDeallocate();
        }

        // Revoke approvals and revnew
        IXGrail(xGRAIL).approveUsage(oldYieldBooster, 0);
        IXGrail(xGRAIL).approveUsage(newYieldBooster, type(uint256).max);

        // reallocate
        uint256 amountToReallocate = _selfBalance(xGRAIL);
        if (amountToReallocate > 0) {
            IXGrail(xGRAIL).allocate(newYieldBooster, amountToReallocate, _getAllocationData());
        }

        yieldBooster = newYieldBooster;
        return true;
    }

    function _increaseNftPoolPosition(uint256 amountLp) internal returns (uint256 amountLpAccountedForUser) {
        // first time minting from this contract
        if (positionId == POSITION_UNINITIALIZED) {
            positionId = ICamelotNFTPool(nftPool).lastTokenId() + 1;
            ICamelotNFTPool(nftPool).createPosition(amountLp, 0);

            _depositToNitroPool();

            return amountLp - MINIMUM_LIQUIDITY;
        } else {
            // nftPool allows adding to position even if the position is in NitroPool
            ICamelotNFTPool(nftPool).addToPosition(positionId, amountLp);
            return amountLp;
        }
    }

    function _decreaseNftPoolPosition(uint256 amountLp) internal {
        _withdrawFromNitroPool();
        ICamelotNFTPool(nftPool).withdrawFromPosition(positionId, amountLp);
        _depositToNitroPool();
    }

    function _depositToNitroPool() internal {
        // Nitro pool's on receive callback will execute the accounting logic
        if (nitroPool == address(0) || positionId == POSITION_UNINITIALIZED) return;
        IERC721(nftPool).safeTransferFrom(address(this), nitroPool, positionId);
    }

    function _withdrawFromNitroPool() internal {
        if (nitroPool == address(0) || positionId == POSITION_UNINITIALIZED) return;
        ICamelotNitroPool(nitroPool).withdraw(positionId);
    }

    function _getAllocationData() private view returns (bytes memory) {
        return abi.encode(nftPool, positionId);
    }

    /**
     * ==================================================================
     *                      CAMELOT NFT RELATED
     * ==================================================================
     */

    function onERC721Received(
        address,
        address,
        uint256 tokenId,
        bytes calldata
    ) external view ensureValidTokenId(tokenId) returns (bytes4) {
        return _ERC721_RECEIVED;
    }

    function onNFTHarvest(
        address,
        address,
        uint256 tokenId,
        uint256,
        uint256
    ) external view ensureValidTokenId(tokenId) returns (bool) {
        return true;
    }

    function onNFTAddToPosition(
        address,
        uint256 tokenId,
        uint256
    ) external view ensureValidTokenId(tokenId) returns (bool) {
        return true;
    }

    function onNFTWithdraw(address, uint256 tokenId, uint256) external view ensureValidTokenId(tokenId) returns (bool) {
        return true;
    }
}
