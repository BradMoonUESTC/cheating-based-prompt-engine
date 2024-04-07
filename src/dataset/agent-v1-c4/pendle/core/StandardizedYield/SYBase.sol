// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "../../interfaces/IStandardizedYield.sol";

import "../erc20/PendleERC20Permit.sol";

import "../libraries/math/PMath.sol";
import "../libraries/TokenHelper.sol";
import "../libraries/ArrayLib.sol";
import "../libraries/Errors.sol";
import "../libraries/BoringOwnableUpgradeable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

abstract contract SYBase is IStandardizedYield, PendleERC20Permit, TokenHelper, BoringOwnableUpgradeable, Pausable {
    using PMath for uint256;

    address public immutable yieldToken;

    constructor(
        string memory _name,
        string memory _symbol,
        address _yieldToken
    ) PendleERC20Permit(_name, _symbol, IERC20Metadata(_yieldToken).decimals()) initializer {
        yieldToken = _yieldToken;
        __BoringOwnable_init();
    }

    // solhint-disable no-empty-blocks
    receive() external payable {}

    /*///////////////////////////////////////////////////////////////
                    DEPOSIT/REDEEM USING BASE TOKENS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IStandardizedYield-deposit}
     */
    function deposit(
        address receiver,
        address tokenIn,
        uint256 amountTokenToDeposit,
        uint256 minSharesOut
    ) external payable nonReentrant returns (uint256 amountSharesOut) {
        if (!isValidTokenIn(tokenIn)) revert Errors.SYInvalidTokenIn(tokenIn);
        if (amountTokenToDeposit == 0) revert Errors.SYZeroDeposit();

        _transferIn(tokenIn, msg.sender, amountTokenToDeposit);

        amountSharesOut = _deposit(tokenIn, amountTokenToDeposit);
        if (amountSharesOut < minSharesOut) revert Errors.SYInsufficientSharesOut(amountSharesOut, minSharesOut);

        _mint(receiver, amountSharesOut);
        emit Deposit(msg.sender, receiver, tokenIn, amountTokenToDeposit, amountSharesOut);
    }

    /**
     * @dev See {IStandardizedYield-redeem}
     */
    function redeem(
        address receiver,
        uint256 amountSharesToRedeem,
        address tokenOut,
        uint256 minTokenOut,
        bool burnFromInternalBalance
    ) external nonReentrant returns (uint256 amountTokenOut) {
        if (!isValidTokenOut(tokenOut)) revert Errors.SYInvalidTokenOut(tokenOut);
        if (amountSharesToRedeem == 0) revert Errors.SYZeroRedeem();

        if (burnFromInternalBalance) {
            _burn(address(this), amountSharesToRedeem);
        } else {
            _burn(msg.sender, amountSharesToRedeem);
        }

        amountTokenOut = _redeem(receiver, tokenOut, amountSharesToRedeem);
        if (amountTokenOut < minTokenOut) revert Errors.SYInsufficientTokenOut(amountTokenOut, minTokenOut);
        emit Redeem(msg.sender, receiver, tokenOut, amountSharesToRedeem, amountTokenOut);
    }

    /**
     * @notice mint shares based on the deposited base tokens
     * @param tokenIn base token address used to mint shares
     * @param amountDeposited amount of base tokens deposited
     * @return amountSharesOut amount of shares minted
     */
    function _deposit(address tokenIn, uint256 amountDeposited) internal virtual returns (uint256 amountSharesOut);

    /**
     * @notice redeems base tokens based on amount of shares to be burned
     * @param tokenOut address of the base token to be redeemed
     * @param amountSharesToRedeem amount of shares to be burned
     * @return amountTokenOut amount of base tokens redeemed
     */
    function _redeem(
        address receiver,
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal virtual returns (uint256 amountTokenOut);

    /*///////////////////////////////////////////////////////////////
                               EXCHANGE-RATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IStandardizedYield-exchangeRate}
     */
    function exchangeRate() external view virtual override returns (uint256 res);

    /*///////////////////////////////////////////////////////////////
                               REWARDS-RELATED
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IStandardizedYield-claimRewards}
     */
    function claimRewards(address /*user*/) external virtual override returns (uint256[] memory rewardAmounts) {
        rewardAmounts = new uint256[](0);
    }

    /**
     * @dev See {IStandardizedYield-getRewardTokens}
     */
    function getRewardTokens() external view virtual override returns (address[] memory rewardTokens) {
        rewardTokens = new address[](0);
    }

    /**
     * @dev See {IStandardizedYield-accruedRewards}
     */
    function accruedRewards(address /*user*/) external view virtual override returns (uint256[] memory rewardAmounts) {
        rewardAmounts = new uint256[](0);
    }

    function rewardIndexesCurrent() external virtual override returns (uint256[] memory indexes) {
        indexes = new uint256[](0);
    }

    function rewardIndexesStored() external view virtual override returns (uint256[] memory indexes) {
        indexes = new uint256[](0);
    }

    /*///////////////////////////////////////////////////////////////
                MISC METADATA FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) external view virtual returns (uint256 amountSharesOut) {
        if (!isValidTokenIn(tokenIn)) revert Errors.SYInvalidTokenIn(tokenIn);
        return _previewDeposit(tokenIn, amountTokenToDeposit);
    }

    function previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) external view virtual returns (uint256 amountTokenOut) {
        if (!isValidTokenOut(tokenOut)) revert Errors.SYInvalidTokenOut(tokenOut);
        return _previewRedeem(tokenOut, amountSharesToRedeem);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function _beforeTokenTransfer(address, address, uint256) internal virtual override whenNotPaused {}

    function _previewDeposit(
        address tokenIn,
        uint256 amountTokenToDeposit
    ) internal view virtual returns (uint256 amountSharesOut);

    function _previewRedeem(
        address tokenOut,
        uint256 amountSharesToRedeem
    ) internal view virtual returns (uint256 amountTokenOut);

    function getTokensIn() public view virtual returns (address[] memory res);

    function getTokensOut() public view virtual returns (address[] memory res);

    function isValidTokenIn(address token) public view virtual returns (bool);

    function isValidTokenOut(address token) public view virtual returns (bool);
}
