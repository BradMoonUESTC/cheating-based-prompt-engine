// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/ERC20.sol";
import {Ownable} from "@openzeppelin/Ownable.sol";
import {Pausable} from "@openzeppelin/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/SafeERC20.sol";
import {IHEU} from "./interfaces/IHEU.sol";
import {IEsHEU} from "./interfaces/IEsHEU.sol";

/// @title EsHEU
/// @notice Escrowed HEU token contract.
contract EsHEU is IEsHEU, ERC20, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IHEU;

    /// CONSTANTS ///

    /// @notice HEU token address.
    IHEU public immutable heu;

    /// STORAGE ///

    /// @notice Vest period.
    uint256 public vestPeriod = 365 days;

    /// @notice They multiplier to apply penalty on remaining token.
    ///         1e18 is 100%
    uint256 public penaltyMultiplier = 0.1e18;

    /// @notice Vest information of user for vest id.
    mapping(address => mapping(uint256 => VestInfo)) public vestInfo;

    /// @notice The number of vests of user.
    mapping(address => uint256) public vestCount;

    /// @param heu_ token address
    constructor(address heu_)
        ERC20("Escrowed Heurist", "esHEU")
        Ownable(msg.sender)
    {
        if (heu_ == address(0)) {
            revert EsHEU__HEUAddressIsInvalid();
        }

        heu = IHEU(heu_);
    }

    /// External Functions ///

    /// @inheritdoc IEsHEU
    function pause() external override onlyOwner {
        _pause();
    }

    /// @inheritdoc IEsHEU
    function unpause() external override onlyOwner {
        _unpause();
    }

    /// @inheritdoc IEsHEU
    function setVestPeriod(uint256 newPeriod) external override onlyOwner {
        if (newPeriod == 0) {
            revert EsHEU__VestPeriodIsInvalid();
        }

        vestPeriod = newPeriod;

        emit SetVestPeriod(newPeriod);
    }

    /// @inheritdoc IEsHEU
    function setPenaltyMultiplier(uint256 newMultiplier)
        external
        override
        onlyOwner
    {
        if (newMultiplier > 1e18) {
            revert EsHEU__PenaltyMultiplierIsInvalid();
        }

        penaltyMultiplier = newMultiplier;

        emit SetPenaltyMultiplier(newMultiplier);
    }

    /// @inheritdoc IEsHEU
    function donate(uint256 amount) external override onlyOwner {
        heu.safeTransferFrom(msg.sender, address(this), amount);

        emit Donate(amount);
    }

    /// @inheritdoc IEsHEU
    function lock(uint256 amount)
        external
        override
        whenNotPaused
        nonReentrant
    {
        if (amount == 0) {
            revert EsHEU__LockAmountIsInvalid();
        }

        uint256 mintAmount = amount * 1e18 / _exchangeRate();

        heu.safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, mintAmount);

        emit Lock(amount, mintAmount);
    }

    /// @inheritdoc IEsHEU
    function vest(uint256 amount)
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256 id)
    {
        if (amount == 0) {
            revert EsHEU__VestAmountIsInvalid();
        }

        id = vestCount[msg.sender];

        vestInfo[msg.sender][id] =
            VestInfo(amount, block.timestamp, block.timestamp + vestPeriod);
        vestCount[msg.sender] = id + 1;

        _transfer(msg.sender, address(this), amount);

        emit Vest(id, amount, vestPeriod);
    }

    /// @inheritdoc IEsHEU
    function cancelVest(uint256 id)
        external
        override
        whenNotPaused
        nonReentrant
    {
        uint256 amount = vestInfo[msg.sender][id].amount;

        if (amount == 0) {
            revert EsHEU__NoVestForId();
        }

        _transfer(address(this), msg.sender, amount);

        delete vestInfo[msg.sender][id];

        emit CancelVest(id, amount);
    }

    /// @inheritdoc IEsHEU
    function claim(uint256 id)
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256 amount, uint256 heuAmount, uint256 penalty)
    {
        (amount, heuAmount, penalty) = _calcClaimAmount(id);

        VestInfo storage info = vestInfo[msg.sender][id];

        if (info.amount > amount) {
            info.amount -= amount;
            info.start = block.timestamp;
        } else {
            delete vestInfo[msg.sender][id];
        }

        heu.safeTransfer(msg.sender, heuAmount);
        _burn(address(this), amount);

        emit Claim(id, amount, heuAmount, penalty);
    }

    /// @inheritdoc IEsHEU
    function claimableAmount(uint256 id)
        external
        view
        override
        returns (uint256 amount, uint256 heuAmount, uint256 penalty)
    {
        (amount, heuAmount, penalty) = _calcClaimAmount(id);
    }

    /// @inheritdoc IEsHEU
    function exchangeRate() external view override returns (uint256) {
        return _exchangeRate();
    }

    /// Internal Functions ///

    /// @notice Return estimated amount of HEU token and penalty for claim.
    /// @param id The id of the vesting.
    /// @return amount The burned amount of esHEU to claim HEU.
    /// @return heuAmount The estimated amount of HEU.
    /// @return penalty The estimated penalty.
    function _calcClaimAmount(uint256 id)
        internal
        view
        returns (uint256 amount, uint256 heuAmount, uint256 penalty)
    {
        VestInfo storage info = vestInfo[msg.sender][id];

        uint256 vestAmount = info.amount;

        if (vestAmount == 0) {
            revert EsHEU__NoVestForId();
        }

        if (block.timestamp >= info.end) {
            amount = vestAmount;
        } else {
            amount = vestAmount * (block.timestamp - info.start)
                / (info.end - info.start);
            penalty = (vestAmount - amount) * penaltyMultiplier / 1e18;
        }

        heuAmount = amount * _exchangeRate() / 1e18;

        if (penalty > 0) {
            amount += penalty;
        }
    }

    /// @notice Returns exchange rate between HEU and esHEU.
    /// @return Exchange rate between HEU and esHEU.
    function _exchangeRate() internal view returns (uint256) {
        uint256 totalHEU = heu.balanceOf(address(this));
        uint256 totalSupply = totalSupply();

        if (totalHEU == 0 || totalSupply == 0) {
            return 1e18;
        }

        return totalHEU * 1e18 / totalSupply;
    }
}
