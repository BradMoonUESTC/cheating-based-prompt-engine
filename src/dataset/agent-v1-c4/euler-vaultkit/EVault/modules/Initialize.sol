// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {IInitialize, IERC20} from "../IEVault.sol";
import {Base} from "../shared/Base.sol";
import {BorrowUtils} from "../shared/BorrowUtils.sol";
import {DToken} from "../DToken.sol";
import {ProxyUtils} from "../shared/lib/ProxyUtils.sol";
import {RevertBytes} from "../shared/lib/RevertBytes.sol";
import {AddressUtils} from "../shared/lib/AddressUtils.sol";

import "../shared/Constants.sol";
import "../shared/types/Types.sol";

/// @title InitializeModule
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice An EVault module implementing the initialization of the new vault contract
abstract contract InitializeModule is IInitialize, BorrowUtils {
    using TypesLib for uint16;

    // Initial value of the interest accumulator: 1 ray
    uint256 internal constant INITIAL_INTEREST_ACCUMULATOR = 1e27;
    // Default fee charged on newly accrued interest in CONFIG_SCALE: 10%
    uint16 internal constant DEFAULT_INTEREST_FEE = 0.1e4;

    /// @inheritdoc IInitialize
    function initialize(address proxyCreator) public virtual reentrantOK {
        if (initialized) revert E_Initialized();
        initialized = true;

        // Validate proxy immutables

        // Calldata should include: signature and abi encoded creator address (4 + 32 bytes), followed by proxy metadata
        if (msg.data.length != 4 + 32 + PROXY_METADATA_LENGTH) revert E_ProxyMetadata();
        (IERC20 asset,,) = ProxyUtils.metadata();
        // Make sure the asset is a contract. Token transfers using a library will not revert if address has no code.
        AddressUtils.checkContract(address(asset));
        // Other constraints on values should be enforced by product line

        // Create sidecar DToken

        address dToken = address(new DToken());

        // Initialize storage

        vaultStorage.lastInterestAccumulatorUpdate = uint48(block.timestamp);
        vaultStorage.interestAccumulator = INITIAL_INTEREST_ACCUMULATOR;
        vaultStorage.interestFee = DEFAULT_INTEREST_FEE.toConfigAmount();
        vaultStorage.creator = vaultStorage.governorAdmin = proxyCreator;

        {
            string memory underlyingSymbol = getTokenSymbol(address(asset));
            uint256 seqId = sequenceRegistry.reserveSeqId(underlyingSymbol);

            vaultStorage.symbol = string(abi.encodePacked("e", underlyingSymbol, "-", uintToString(seqId)));
            vaultStorage.name = string(abi.encodePacked("EVK Vault ", vaultStorage.symbol));
        }

        snapshot.reset();

        // Emit logs

        emit EVaultCreated(proxyCreator, address(asset), dToken);
        logVaultStatus(loadVault(), 0);
    }

    // prevent initialization of the implementation contract
    constructor() {
        initialized = true;
    }

    /// @dev Calls the asset's symbol() method, taking care to handle MKR-like tokens that return bytes32 instead of
    /// string. For tokens that do not implement symbol(), "UNDEFINED" will be returned.
    function getTokenSymbol(address asset) private view returns (string memory) {
        (bool success, bytes memory data) = address(asset).staticcall(abi.encodeCall(IERC20.symbol, ()));
        if (!success) return "UNDEFINED";
        return data.length <= 32 ? string(data) : abi.decode(data, (string));
    }

    /// @dev Converts a uint256 to a decimal string representation
    function uintToString(uint256 n) private pure returns (string memory) {
        unchecked {
            if (n == 0) return "0";

            uint256 len;
            for (uint256 m = n; m != 0; m /= 10) {
                len++;
            }

            bytes memory output = new bytes(len);

            while (len > 0) {
                output[--len] = bytes1(uint8(48 + n % 10)); // 48 is ASCII '0'
                n /= 10;
            }

            return string(output);
        }
    }
}

/// @dev Deployable module contract
contract Initialize is InitializeModule {
    constructor(Integrations memory integrations) Base(integrations) {}
}
