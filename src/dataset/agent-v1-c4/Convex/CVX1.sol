// SPDX-License-Identifier: MIT
/**
 _____
/  __ \
| /  \/ ___  _ ____   _____ _ __ __ _  ___ _ __   ___ ___
| |    / _ \| '_ \ \ / / _ \ '__/ _` |/ _ \ '_ \ / __/ _ \
| \__/\ (_) | | | \ V /  __/ | | (_| |  __/ | | | (_|  __/
 \____/\___/|_| |_|\_/ \___|_|  \__, |\___|_| |_|\___\___|
                                 __/ |
                                |___/
 */

/// @title Cvg-Finance - CVX1
/// @notice ERC20 token. Instead of creating a CVX / cvgCVX stable pool on Curve where the CVX is not compounding we created the CVX1
/// @notice CVX1 is always exchangeable at a 1:1 ratio for CVX.
/// @dev    On the LP CVX1 / cvgCVX, all CVX used to mint the CVX1 is staked in the StkCvx, farming cvxCRV
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "../../../interfaces/ICvgControlTowerV2.sol";

contract CVX1 is ERC20Upgradeable, Ownable2StepUpgradeable {
    /// @dev Convergence control tower
    ICvgControlTowerV2 public constant cvgControlTower = ICvgControlTowerV2(0xB0Afc8363b8F36E0ccE5D54251e20720FfaeaeE7);

    /// @dev Convex token
    IERC20 public constant CVX = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);

    /// @dev cvxCRV token
    IERC20 public constant CVX_CRV = IERC20(0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7);

    /// @dev Convex CVX reward pool contract. Stake CVX & receives cvxCRV.
    ICvxRewardPool public cvxRewardPool;

    /* =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-=
                        CONSTRUCTOR & INIT
    =-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=--=-=-=-= */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice initialize function
    function initialize(
        string memory _name,
        string memory _symbol,
        ICvxRewardPool _cvxRewardPool
    ) external initializer {
        __ERC20_init(_name, _symbol);

        cvxRewardPool = _cvxRewardPool;
        CVX.approve(address(_cvxRewardPool), type(uint256).max);

        _transferOwnership(cvgControlTower.treasuryDao());
    }

    /**
     * @notice Mint an amount of CVX1 to the caller in exchange of the same amount of CVX.
     * @param amount Amount of CVX to transfer & CVX1 to mint.
     */
    function mint(address receiver, uint256 amount) external {
        CVX.transferFrom(msg.sender, address(this), amount);

        _mint(receiver, amount);
    }

    /**
     * @notice Withdraw an amount of CVX against the burn of CVX1.
     * @param amount Amount of CVX to withdraw.
     */
    function withdraw(uint256 amount, address receiver) external {
        _burn(msg.sender, amount);

        uint256 cvxBalance = CVX.balanceOf(address(this));
        if (amount > cvxBalance) {
            cvxRewardPool.withdraw(amount - cvxBalance, false);
        }

        CVX.transfer(receiver, amount);
    }

    /**
     * @notice Stake the whole CVX balance of this contract on CVX Reward Pool contract.
     */
    function stake() external {
        if (CVX.balanceOf(address(this)) > 0) cvxRewardPool.stakeAll();
    }

    /**
     * @notice Get the rewards from Convex staking and send them to Treasury POD.
     */
    function getReward() external {
        cvxRewardPool.getReward(false);

        /// @dev transfer cvxCRV tokens
        CVX_CRV.transfer(cvgControlTower.treasuryPod(), CVX_CRV.balanceOf(address(this)));
    }

    /**
     * @notice Send the extra rewards or recovered tokens from Convex staking to Treasury POD.
     */
    function recoverRewards(IERC20[] calldata erc20s) external {
        uint256 extraRewardsLength = erc20s.length;
        address treasuryPod = cvgControlTower.treasuryPod();

        for (uint256 i; i < extraRewardsLength; ) {
            IERC20 _rewardToken = IERC20(erc20s[i]);
            require(_rewardToken != CVX, "CANNOT_GET_CVX");
            _rewardToken.transfer(treasuryPod, _rewardToken.balanceOf(address(this)));
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Set a new Convex reward pool.
     * @dev It removes the allowance of CVX to the previous contract.
     * @param _cvxRewardPool Address of the new contract.
     */
    function setCvxRewardPool(ICvxRewardPool _cvxRewardPool) external onlyOwner {
        CVX.approve(address(cvxRewardPool), 0);
        CVX.approve(address(_cvxRewardPool), type(uint256).max);

        cvxRewardPool = _cvxRewardPool;
    }
}
interface ICvxRewardPool {
    function stakeAll() external;
    function withdraw(uint256 _amount, bool claim) external;
    function getReward(bool _stake) external;
    function extraRewards(uint256 index) external view returns (address);
    function extraRewardsLength() external view returns (uint256);
}
