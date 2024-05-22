// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "./IProtocolConfig.sol";

contract ProtocolConfig is IProtocolConfig {
    error E_OnlyAdmin();
    error E_InvalidVault();
    error E_InvalidReceiver();
    error E_InvalidConfigValue();
    error E_InvalidAdmin();

    struct InterestFeeRange {
        bool exists;
        uint16 minInterestFee;
        uint16 maxInterestFee;
    }

    struct ProtocolFeeConfig {
        bool exists;
        address feeReceiver;
        uint16 protocolFeeShare;
    }

    // max valid value of the EVault's ConfigAmount custom type, signifying 100%
    uint16 internal constant CONFIG_SCALE = 1e4;

    /// @dev admin address
    address public admin;
    /// @dev protocol fee receiver, unless a vault has it configured otherwise
    address public feeReceiver;
    /// @dev protocol fee share, except for vaults configured otherwise
    uint16 internal protocolFeeShare;

    /// @dev min interest fee, except for vaults configured otherwise
    uint16 internal minInterestFee;
    /// @dev max interest fee, except for vaults configured otherwise
    uint16 internal maxInterestFee;

    /// @dev per-vault configuration of min/max interest fee range, takes priority over defaults
    mapping(address vault => InterestFeeRange) internal _interestFeeRanges;
    /// @dev per-vault configuration of protocol fee config, takes priority over defaults
    mapping(address vault => ProtocolFeeConfig) internal _protocolFeeConfig;

    /// @notice Set global default allowed interest fee limits
    /// @param newMinInterestFee lower limit of allowed interest fee
    /// @param newMaxInterestFee upper limit of allowed interest fee
    event SetInterestFeeRange(uint16 newMinInterestFee, uint16 newMaxInterestFee);

    /// @notice Set new fee receiver address
    /// @param newFeeReceiver new fee receiver address
    event SetFeeReceiver(address indexed newFeeReceiver);

    /// @notice Set allowed interest fee limits override for a vault
    /// @param vault address of the vault
    /// @param exists if true a new setting was recorded, if false the override was disabled for the vault
    /// @param minInterestFee lower limit of allowed interest fee
    /// @param maxInterestFee upper limit of allowed interest fee
    event SetVaultInterestFeeRange(address indexed vault, bool exists, uint16 minInterestFee, uint16 maxInterestFee);

    /// @notice Set interest fee configuration override for a vault
    /// @param vault address of the vault
    /// @param exists if true a new setting was recorded, if false the override was disabled for the vault
    /// @param feeReceiver address to receive protocol fees
    /// @param protocolFeeShare new protocol fee share
    event SetFeeConfigSetting(address indexed vault, bool exists, address indexed feeReceiver, uint16 protocolFeeShare);

    /// @notice Set a new global default protocol fee share
    /// @param protocolFeeShare previous default protocol fee share
    /// @param newProtocolFeeShare new default protocol fee share
    event SetProtocolFeeShare(uint16 protocolFeeShare, uint16 newProtocolFeeShare);

    /// @notice Transfer admin rights to a new address
    /// @param newAdmin address of the new admin
    event SetAdmin(address indexed newAdmin);

    /// @dev constructor
    /// @param admin_ admin's address
    /// @param feeReceiver_ the address of the protocol fee receiver
    constructor(address admin_, address feeReceiver_) {
        if (admin_ == address(0)) revert E_InvalidAdmin();
        if (feeReceiver_ == address(0)) revert E_InvalidReceiver();

        admin = admin_;
        feeReceiver = feeReceiver_;

        minInterestFee = 0.1e4;
        maxInterestFee = 1e4;
        protocolFeeShare = 0.1e4;
    }

    /// @inheritdoc IProtocolConfig
    function isValidInterestFee(address vault, uint16 interestFee) external view returns (bool) {
        InterestFeeRange memory range = _interestFeeRanges[vault];

        if (range.exists) {
            return interestFee >= range.minInterestFee && interestFee <= range.maxInterestFee;
        }

        return interestFee >= minInterestFee && interestFee <= maxInterestFee;
    }

    /// @inheritdoc IProtocolConfig
    function protocolFeeConfig(address vault) external view returns (address, uint16) {
        ProtocolFeeConfig memory config = _protocolFeeConfig[vault];

        if (config.exists) {
            return (config.feeReceiver, config.protocolFeeShare);
        }

        return (feeReceiver, protocolFeeShare);
    }

    /// @inheritdoc IProtocolConfig
    function interestFeeRange(address vault) external view returns (uint16, uint16) {
        InterestFeeRange memory ranges = _interestFeeRanges[vault];

        if (ranges.exists) {
            return (ranges.minInterestFee, ranges.maxInterestFee);
        }

        return (minInterestFee, maxInterestFee);
    }

    // Admin functions

    /// @dev modifier to check if sender is admin address
    modifier onlyAdmin() {
        if (msg.sender != admin) revert E_OnlyAdmin();

        _;
    }

    /// @notice set admin address
    /// @param newAdmin admin's address
    function setAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert E_InvalidAdmin();

        admin = newAdmin;

        emit SetAdmin(newAdmin);
    }

    /// @notice set protocol fee receiver
    /// @dev can only be called by admin
    /// @param newReceiver new receiver address
    function setFeeReceiver(address newReceiver) external onlyAdmin {
        if (newReceiver == address(0)) revert E_InvalidReceiver();

        feeReceiver = newReceiver;

        emit SetFeeReceiver(newReceiver);
    }

    /// @notice set protocol fee share
    /// @dev can only be called by admin
    /// @param newProtocolFeeShare new protocol fee share
    function setProtocolFeeShare(uint16 newProtocolFeeShare) external onlyAdmin {
        if (newProtocolFeeShare > CONFIG_SCALE) revert E_InvalidConfigValue();

        emit SetProtocolFeeShare(protocolFeeShare, newProtocolFeeShare);

        protocolFeeShare = newProtocolFeeShare;
    }

    /// @notice set generic min interest fee
    /// @dev can only be called by admin
    /// @param minInterestFee_ new min interest fee
    /// @param maxInterestFee_ new max interest fee
    function setInterestFeeRange(uint16 minInterestFee_, uint16 maxInterestFee_) external onlyAdmin {
        if (maxInterestFee_ > CONFIG_SCALE || minInterestFee_ > maxInterestFee_) revert E_InvalidConfigValue();

        minInterestFee = minInterestFee_;
        maxInterestFee = maxInterestFee_;

        emit SetInterestFeeRange(minInterestFee_, maxInterestFee_);
    }

    /// @notice set interest fee range for specific vault
    /// @dev can only be called by admin
    /// @param vault vault's address
    /// @param exists_ a boolean to set or unset the ranges. When false, the generic ranges will be used for the vault
    /// @param minInterestFee_ min interest fee
    /// @param maxInterestFee_ max interest fee
    function setVaultInterestFeeRange(address vault, bool exists_, uint16 minInterestFee_, uint16 maxInterestFee_)
        external
        onlyAdmin
    {
        if (vault == address(0)) revert E_InvalidVault();
        if (maxInterestFee_ > CONFIG_SCALE || minInterestFee_ > maxInterestFee_) revert E_InvalidConfigValue();

        _interestFeeRanges[vault] =
            InterestFeeRange({exists: exists_, minInterestFee: minInterestFee_, maxInterestFee: maxInterestFee_});

        emit SetVaultInterestFeeRange(vault, exists_, minInterestFee_, maxInterestFee_);
    }

    /// @notice set protocol fee config for specific vault
    /// @dev can only be called by admin
    /// @param vault vault's address
    /// @param exists_ a boolean to set or unset the config. When false, the generic config will be used for the vault
    /// @param feeReceiver_ fee receiver address
    /// @param protocolFeeShare_ fee share
    function setVaultFeeConfig(address vault, bool exists_, address feeReceiver_, uint16 protocolFeeShare_)
        external
        onlyAdmin
    {
        if (vault == address(0)) revert E_InvalidVault();
        if (exists_ && feeReceiver_ == address(0)) revert E_InvalidReceiver();
        if (protocolFeeShare_ > CONFIG_SCALE) revert E_InvalidConfigValue();

        _protocolFeeConfig[vault] =
            ProtocolFeeConfig({exists: exists_, feeReceiver: feeReceiver_, protocolFeeShare: protocolFeeShare_});

        emit SetFeeConfigSetting(vault, exists_, feeReceiver_, protocolFeeShare_);
    }
}
