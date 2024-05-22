// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../utils/mocks/Vault.sol";
import "../../evc/EthereumVaultConnectorHarness.sol";
import "openzeppelin/utils/cryptography/ECDSA.sol";
import {ShortStrings, ShortString} from "openzeppelin/utils/ShortStrings.sol";

abstract contract EIP712 {
    using ShortStrings for *;

    bytes32 internal constant _TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 internal immutable _hashedName;
    bytes32 internal immutable _hashedVersion;

    ShortString private immutable _name;
    ShortString private immutable _version;
    string private _nameFallback;
    string private _versionFallback;

    /**
     * @dev Initializes the domain separator.
     *
     * The meaning of `name` and `version` is specified in
     * https://eips.ethereum.org/EIPS/eip-712#definition-of-domainseparator[EIP 712]:
     *
     * - `name`: the user readable name of the signing domain, i.e. the name of the DApp or the protocol.
     * - `version`: the current major version of the signing domain.
     *
     * NOTE: These parameters cannot be changed except through a xref:learn::upgrading-smart-contracts.adoc[smart
     * contract upgrade].
     */
    constructor(string memory name, string memory version) {
        _name = name.toShortStringWithFallback(_nameFallback);
        _version = version.toShortStringWithFallback(_versionFallback);
        _hashedName = keccak256(bytes(name));
        _hashedVersion = keccak256(bytes(version));
    }

    /**
     * @dev Returns the domain separator for the current chain.
     */
    function _domainSeparatorV4() internal view returns (bytes32) {
        return _buildDomainSeparator();
    }

    function _buildDomainSeparator() internal view virtual returns (bytes32) {
        return bytes32(0);
    }

    /**
     * @dev Given an already https://eips.ethereum.org/EIPS/eip-712#definition-of-hashstruct[hashed struct], this
     * function returns the hash of the fully encoded EIP712 message for this domain.
     *
     * This hash can be used together with {ECDSA-recover} to obtain the signer of a message. For example:
     *
     * ```solidity
     * bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
     *     keccak256("Mail(address to,string contents)"),
     *     mailTo,
     *     keccak256(bytes(mailContents))
     * )));
     * address signer = ECDSA.recover(digest, signature);
     * ```
     */
    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
        return ECDSA.toTypedDataHash(_domainSeparatorV4(), structHash);
    }
}

contract SignerECDSA is EIP712, Test {
    EthereumVaultConnector private immutable evc;
    uint256 private privateKey;

    bytes32 internal constant PERMIT_TYPEHASH = keccak256(
        "Permit(address signer,address sender,uint256 nonceNamespace,uint256 nonce,uint256 deadline,uint256 value,bytes data)"
    );

    constructor(EthereumVaultConnector _evc) EIP712(_evc.name(), _evc.version()) {
        evc = _evc;
    }

    function setPrivateKey(uint256 _privateKey) external {
        privateKey = _privateKey;
    }

    function _buildDomainSeparator() internal view override returns (bytes32) {
        return keccak256(abi.encode(_TYPE_HASH, _hashedName, _hashedVersion, block.chainid, address(evc)));
    }

    function signPermit(
        address signer,
        address sender,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        uint256 value,
        bytes calldata data
    ) external view returns (bytes memory signature) {
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, signer, sender, nonceNamespace, nonce, deadline, value, keccak256(data))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, _hashTypedDataV4(structHash));
        signature = abi.encodePacked(r, s, v);
    }
}

contract SignerERC1271 is EIP712, IERC1271 {
    EthereumVaultConnector private immutable evc;
    bytes32 private signatureHash;
    bytes32 private permitHash;

    bytes32 internal constant PERMIT_TYPEHASH = keccak256(
        "Permit(address signer,address sender,uint256 nonceNamespace,uint256 nonce,uint256 deadline,uint256 value,bytes data)"
    );

    constructor(EthereumVaultConnector _evc) EIP712(_evc.name(), _evc.version()) {
        evc = _evc;
    }

    function _buildDomainSeparator() internal view override returns (bytes32) {
        return keccak256(abi.encode(_TYPE_HASH, _hashedName, _hashedVersion, block.chainid, address(evc)));
    }

    function setSignatureHash(bytes calldata signature) external {
        signatureHash = keccak256(signature);
    }

    function setPermitHash(
        address signer,
        address sender,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        uint256 value,
        bytes calldata data
    ) external {
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, signer, sender, nonceNamespace, nonce, deadline, value, keccak256(data))
        );
        permitHash = _hashTypedDataV4(structHash);
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue) {
        if (hash == permitHash && signatureHash == keccak256(signature)) {
            magicValue = this.isValidSignature.selector;
        }
    }
}

contract EthereumVaultConnectorWithFallback is EthereumVaultConnectorHarness {
    bytes32 internal expectedHash;
    uint256 internal expectedValue;
    bool internal shouldRevert;
    bool public fallbackCalled;

    function setExpectedHash(bytes calldata data) external {
        expectedHash = keccak256(data);
    }

    function setExpectedValue(uint256 value) external {
        expectedValue = value;
    }

    function setShouldRevert(bool sr) external {
        shouldRevert = sr;
    }

    function clearFallbackCalled() external {
        fallbackCalled = false;
    }

    fallback(bytes calldata data) external payable returns (bytes memory) {
        if (shouldRevert) revert("fallback reverted");

        if (expectedHash == keccak256(data) && expectedValue == msg.value && address(this) == msg.sender) {
            fallbackCalled = true;
        }

        return data;
    }
}

contract PermitTest is Test {
    EthereumVaultConnectorWithFallback internal evc;
    SignerECDSA internal signerECDSA;
    SignerERC1271 internal signerERC1271;

    event NonceUsed(bytes19 indexed addressPrefix, uint256 indexed nonceNamespace, uint256 nonce);
    event CallWithContext(
        address indexed caller,
        bytes19 indexed onBehalfOfAddressPrefix,
        address onBehalfOfAccount,
        address indexed targetContract,
        bytes4 selector
    );

    function setUp() public {
        evc = new EthereumVaultConnectorWithFallback();
        signerECDSA = new SignerECDSA(evc);
    }

    function test_ECDSA_Permit(
        uint256 privateKey,
        address sender,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        bytes memory data,
        uint16 value
    ) public {
        vm.assume(
            privateKey > 0
                && privateKey < 115792089237316195423570985008687907852837564279074904382605163141518161494337
        );
        address alice = vm.addr(privateKey);
        bytes19 addressPrefix = evc.getAddressPrefix(alice);
        address msgSender = sender == address(0) ? address(uint160(uint256(keccak256(abi.encode(alice))))) : sender;
        data = abi.encode(keccak256(data));

        vm.assume(!evc.haveCommonOwner(alice, address(0)) && alice != address(evc));
        vm.assume(nonce > 0 && nonce < type(uint256).max);

        vm.warp(deadline);
        vm.deal(msgSender, type(uint128).max);
        signerECDSA.setPrivateKey(privateKey);

        if (nonce > 0) {
            vm.prank(alice);
            evc.setNonce(addressPrefix, nonceNamespace, nonce);
        }

        evc.clearFallbackCalled();
        evc.setExpectedHash(data);
        evc.setExpectedValue(value);

        bytes memory signature = signerECDSA.signPermit(alice, sender, nonceNamespace, nonce, deadline, value, data);

        vm.expectEmit(true, true, false, true, address(evc));
        emit NonceUsed(evc.getAddressPrefix(alice), nonceNamespace, nonce);
        vm.expectEmit(true, true, true, true, address(evc));
        emit CallWithContext(msgSender, evc.getAddressPrefix(alice), alice, address(evc), bytes4(data));

        vm.startPrank(msgSender);

        evc.permit{value: msgSender.balance}(alice, sender, nonceNamespace, nonce, deadline, value, data, signature);
        assertTrue(evc.fallbackCalled());

        // it's not possible to carry out a reply attack
        vm.expectRevert(Errors.EVC_InvalidNonce.selector);
        evc.permit{value: msgSender.balance}(alice, sender, nonceNamespace, nonce, deadline, value, data, signature);
    }

    function test_ERC1271_Permit(
        address sender,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        bytes memory data,
        bytes calldata signature,
        uint16 value
    ) public {
        address alice = address(new SignerERC1271(evc));
        bytes19 addressPrefix = evc.getAddressPrefix(alice);
        address msgSender = sender == address(0) ? address(uint160(uint256(keccak256(abi.encode(alice))))) : sender;
        data = abi.encode(keccak256(data));

        vm.assume(msgSender != address(evc));
        vm.assume(!evc.haveCommonOwner(alice, address(0)));
        vm.assume(nonce > 0 && nonce < type(uint256).max);

        vm.warp(deadline);
        vm.deal(msgSender, type(uint128).max);
        SignerERC1271(alice).setSignatureHash(signature);

        if (nonce > 0) {
            vm.prank(alice);
            evc.setNonce(addressPrefix, nonceNamespace, nonce);
        }

        evc.clearFallbackCalled();
        evc.setExpectedHash(data);
        evc.setExpectedValue(value);

        SignerERC1271(alice).setPermitHash(alice, sender, nonceNamespace, nonce, deadline, value, data);

        vm.expectEmit(true, true, false, true, address(evc));
        emit NonceUsed(evc.getAddressPrefix(alice), nonceNamespace, nonce);
        vm.expectEmit(true, true, true, true, address(evc));
        emit CallWithContext(msgSender, evc.getAddressPrefix(alice), alice, address(evc), bytes4(data));

        vm.startPrank(msgSender);

        evc.permit{value: msgSender.balance}(alice, sender, nonceNamespace, nonce, deadline, value, data, signature);
        assertTrue(evc.fallbackCalled());

        // it's not possible to carry out a reply attack
        vm.expectRevert(Errors.EVC_InvalidNonce.selector);
        evc.permit{value: msgSender.balance}(alice, sender, nonceNamespace, nonce, deadline, value, data, signature);
    }

    function test_RevertIfNestedPermit_Permit(
        uint256 privateKey,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        uint128 value,
        bytes memory data2
    ) public {
        vm.assume(
            privateKey > 0
                && privateKey < 115792089237316195423570985008687907852837564279074904382605163141518161494337
        );
        address alice = vm.addr(privateKey);
        vm.assume(!evc.haveCommonOwner(alice, address(0)) && alice != address(evc));
        bytes19 addressPrefix = evc.getAddressPrefix(alice);
        data2 = abi.encode(keccak256(data2));
        vm.assume(nonce > 0 && nonce < type(uint256).max - 1);

        vm.warp(deadline);
        vm.deal(address(this), type(uint128).max);
        signerECDSA.setPrivateKey(privateKey);

        if (nonce > 0) {
            vm.prank(alice);
            evc.setNonce(addressPrefix, nonceNamespace, nonce);
        }

        bytes memory signature2 =
            signerECDSA.signPermit(alice, address(this), nonceNamespace, nonce + 1, deadline, 0, data2);
        bytes memory data1 = abi.encodeWithSelector(
            IEVC.permit.selector, alice, address(this), nonceNamespace, nonce + 1, deadline, 0, data2, signature2
        );
        bytes memory signature1 =
            signerECDSA.signPermit(alice, address(this), nonceNamespace, nonce, deadline, value, data1);

        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit{value: value}(alice, address(this), nonceNamespace, nonce, deadline, value, data1, signature1);
    }

    function test_RevertIfSenderInvalid_Permit(
        uint256 privateKey,
        address sender,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        uint256 value,
        bytes memory data,
        bytes calldata signature
    ) public {
        vm.assume(
            privateKey > 0
                && privateKey < 115792089237316195423570985008687907852837564279074904382605163141518161494337
        );
        address alice = vm.addr(privateKey);
        vm.assume(!evc.haveCommonOwner(alice, address(0)) && alice != address(evc));
        bytes19 addressPrefix = evc.getAddressPrefix(alice);
        data = abi.encode(keccak256(data));
        vm.assume(sender != address(0) && sender != address(this));
        vm.assume(nonce > 0 && nonce < type(uint256).max);
        vm.warp(deadline);

        if (nonce > 0) {
            vm.prank(alice);
            evc.setNonce(addressPrefix, nonceNamespace, nonce);
        }

        // reverts if sender is invalid
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, sender, nonceNamespace, nonce, deadline, value, data, signature);
    }

    function test_RevertIfSignerInvalid_Permit(
        address alice,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        uint256 value,
        bytes memory data,
        bytes calldata signature
    ) public {
        alice = address(uint160(bound(uint160(alice), 0, 0xFF)));
        bytes19 addressPrefix = evc.getAddressPrefix(alice);
        data = abi.encode(keccak256(data));
        vm.assume(nonce > 0 && nonce < type(uint256).max);
        vm.warp(deadline);

        if (nonce > 0) {
            vm.prank(alice);
            evc.setNonce(addressPrefix, nonceNamespace, nonce);
        }

        // reverts if signer is zero address
        vm.expectRevert(Errors.EVC_InvalidAddress.selector);
        evc.permit(alice, address(this), nonceNamespace, nonce, deadline, value, data, signature);
    }

    function test_RevertIfNonceInvalid_Permit(
        address alice,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        uint256 value,
        bytes memory data,
        bytes calldata signature
    ) public {
        bytes19 addressPrefix = evc.getAddressPrefix(alice);
        data = abi.encode(keccak256(data));
        vm.assume(!evc.haveCommonOwner(alice, address(0)) && alice != address(evc));
        vm.assume(nonce < type(uint256).max);
        vm.warp(deadline);

        if (nonce > 1) {
            vm.prank(alice);
            evc.setNonce(addressPrefix, nonceNamespace, nonce - 1);

            // reverts if nonce is invalid
            vm.expectRevert(Errors.EVC_InvalidNonce.selector);
            evc.permit(alice, address(this), nonceNamespace, nonce, deadline, value, data, signature);
        }

        vm.prank(alice);
        evc.setNonce(addressPrefix, nonceNamespace, nonce + 1);

        // reverts if nonce is invalid
        vm.expectRevert(Errors.EVC_InvalidNonce.selector);
        evc.permit(alice, address(this), nonceNamespace, nonce, deadline, value, data, signature);
    }

    function test_RevertIfDeadlineMissed_Permit(
        address alice,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        uint256 value,
        bytes memory data,
        bytes calldata signature
    ) public {
        bytes19 addressPrefix = evc.getAddressPrefix(alice);
        data = abi.encode(keccak256(data));
        vm.assume(!evc.haveCommonOwner(alice, address(0)) && alice != address(evc));
        vm.assume(nonce > 0 && nonce < type(uint256).max);
        vm.assume(deadline < type(uint256).max);
        vm.warp(deadline + 1);

        if (nonce > 0) {
            vm.prank(alice);
            evc.setNonce(addressPrefix, nonceNamespace, nonce);
        }

        // reverts if deadline is missed
        vm.expectRevert(Errors.EVC_InvalidTimestamp.selector);
        evc.permit(alice, address(this), nonceNamespace, nonce, deadline, value, data, signature);
    }

    function test_RevertIfValueExceedsBalance_Permit(
        uint256 privateKey,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        uint128 value,
        bytes memory data
    ) public {
        vm.assume(
            privateKey > 0
                && privateKey < 115792089237316195423570985008687907852837564279074904382605163141518161494337
        );
        address alice = vm.addr(privateKey);
        bytes19 addressPrefix = evc.getAddressPrefix(alice);
        data = abi.encode(keccak256(data));
        vm.assume(!evc.haveCommonOwner(alice, address(0)) && alice != address(evc));
        vm.assume(nonce > 0 && nonce < type(uint256).max);
        vm.assume(value > 0);
        vm.warp(deadline);

        signerECDSA.setPrivateKey(privateKey);
        bytes memory signature =
            signerECDSA.signPermit(alice, address(this), nonceNamespace, nonce, deadline, value, data);

        if (nonce > 0) {
            vm.prank(alice);
            evc.setNonce(addressPrefix, nonceNamespace, nonce);
        }

        // reverts if value exceeds balance
        vm.deal(address(evc), value - 1);
        vm.expectRevert(Errors.EVC_InvalidValue.selector);
        evc.permit(alice, address(this), nonceNamespace, nonce, deadline, value, data, signature);

        // succeeds if value does not exceed balance
        vm.deal(address(evc), value);
        evc.permit(alice, address(this), nonceNamespace, nonce, deadline, value, data, signature);
    }

    function test_RevertIfDataIsInvalid_Permit(
        address alice,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        uint256 value,
        bytes calldata signature
    ) public {
        bytes19 addressPrefix = evc.getAddressPrefix(alice);
        vm.assume(!evc.haveCommonOwner(alice, address(0)) && alice != address(evc));
        vm.assume(nonce > 0 && nonce < type(uint256).max);
        vm.warp(deadline);

        if (nonce > 0) {
            vm.prank(alice);
            evc.setNonce(addressPrefix, nonceNamespace, nonce);
        }

        // reverts if data is empty
        vm.expectRevert(Errors.EVC_InvalidData.selector);
        evc.permit(alice, address(this), nonceNamespace, nonce, deadline, value, bytes(""), signature);
    }

    function test_RevertIfCallUnsuccessful_Permit(
        uint256 privateKey,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        uint128 value,
        bytes memory data
    ) public {
        vm.chainId(5); // for coverage
        vm.assume(
            privateKey > 0
                && privateKey < 115792089237316195423570985008687907852837564279074904382605163141518161494337
        );
        address alice = vm.addr(privateKey);
        bytes19 addressPrefix = evc.getAddressPrefix(alice);
        data = abi.encode(keccak256(data));
        signerECDSA.setPrivateKey(privateKey);

        vm.assume(!evc.haveCommonOwner(alice, address(0)) && alice != address(evc));
        vm.assume(nonce > 0 && nonce < type(uint256).max);
        vm.warp(deadline);
        vm.deal(address(evc), value);

        evc.clearFallbackCalled();
        evc.setExpectedHash(data);
        evc.setExpectedValue(value);
        evc.setShouldRevert(true);

        if (nonce > 0) {
            vm.prank(alice);
            evc.setNonce(addressPrefix, nonceNamespace, nonce);
        }

        // reverts if EVC self-call unsuccessful
        bytes memory signature =
            signerECDSA.signPermit(alice, address(this), nonceNamespace, nonce, deadline, value, data);

        vm.expectRevert(bytes("fallback reverted"));
        evc.permit(alice, address(this), nonceNamespace, nonce, deadline, value, data, signature);

        // succeeds if EVC self-call successful
        evc.setShouldRevert(false);

        evc.permit(alice, address(this), nonceNamespace, nonce, deadline, value, data, signature);
        assertTrue(evc.fallbackCalled());
    }

    function test_RevertIfSignerIsNotContractERC1271_Permit(
        address signer,
        uint256 nonceNamespace,
        uint256 nonce,
        uint256 deadline,
        bytes memory data,
        bytes calldata signature,
        uint16 value
    ) public {
        vm.assume(!evc.haveCommonOwner(signer, address(0)) && signer != address(evc));
        vm.assume(nonce > 0 && nonce < type(uint256).max);

        bytes19 addressPrefix = evc.getAddressPrefix(signer);
        data = abi.encode(keccak256(data));

        vm.warp(deadline);
        vm.deal(address(this), type(uint128).max);

        if (nonce > 0) {
            vm.prank(signer);
            evc.setNonce(addressPrefix, nonceNamespace, nonce);
        }

        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit{value: address(this).balance}(
            signer, address(this), nonceNamespace, nonce, deadline, value, data, signature
        );
    }

    function test_RevertIfInvalidECDSASignature_Permit(uint256 privateKey, uint128 deadline) public {
        vm.assume(
            privateKey > 0
                && privateKey < 115792089237316195423570985008687907852837564279074904382605163141518161494337
        );
        address alice = vm.addr(privateKey);
        signerECDSA.setPrivateKey(privateKey);

        vm.assume(!evc.haveCommonOwner(alice, address(0)));
        vm.warp(deadline);

        // ECDSA signature invalid due to signer.
        // ERC-1271 signature invalid as the signer is EOA and isValidSignature() call is unsuccessful
        bytes memory signature =
            signerECDSA.signPermit(address(uint160(alice) + 1), address(this), 0, 0, deadline, 0, bytes("0"));
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);

        // ECDSA signature invalid due to sender.
        // ERC-1271 signature invalid as the signer is EOA and isValidSignature() call is unsuccessful
        signature = signerECDSA.signPermit(address(uint160(alice) + 1), address(0), 0, 0, deadline, 0, bytes("0"));
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);

        // ECDSA signature invalid due to nonce namespace.
        // ERC-1271 signature invalid as the signer is EOA and isValidSignature() call is unsuccessful
        signature = signerECDSA.signPermit(alice, address(this), 1, 0, deadline, 0, bytes("0"));
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);

        // ECDSA signature invalid due to nonce.
        // ERC-1271 signature invalid as the signer is EOA and isValidSignature() call is unsuccessful
        signature = signerECDSA.signPermit(alice, address(this), 0, 1, deadline, 0, bytes("0"));
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);

        // ECDSA signature invalid due to deadline.
        // ERC-1271 signature invalid as the signer is EOA and isValidSignature() call is unsuccessful
        signature = signerECDSA.signPermit(alice, address(this), 0, 0, uint256(deadline) + 1, 0, bytes("0"));
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);

        // ECDSA signature invalid due to value.
        // ERC-1271 signature invalid as the signer is EOA and isValidSignature() call is unsuccessful
        signature = signerECDSA.signPermit(alice, address(this), 0, 0, deadline, 1, bytes("0"));
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);

        // ECDSA signature invalid due to data.
        // ERC-1271 signature invalid as the signer is EOA and isValidSignature() call is unsuccessful
        signature = signerECDSA.signPermit(alice, address(this), 0, 0, deadline, 0, bytes("1"));
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);

        // ECDSA signature invalid (wrong length due to added 1).
        // ERC-1271 signature invalid as the signer is EOA and isValidSignature() call is unsuccessful
        signature = signerECDSA.signPermit(alice, address(this), 0, 0, deadline, 0, bytes("0"));

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        signature = abi.encodePacked(r, s, v, uint8(1));
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);

        // ECDSA signature invalid (r is 0).
        // ERC-1271 signature invalid as the signer is EOA and isValidSignature() call is unsuccessful
        signature = abi.encodePacked(uint256(0), s, v);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);

        // ECDSA signature invalid (s is 0).
        // ERC-1271 signature invalid as the signer is EOA and isValidSignature() call is unsuccessful
        signature = abi.encodePacked(r, uint256(0), v);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);

        // ECDSA signature invalid (v is 0).
        // ERC-1271 signature invalid as the signer is EOA and isValidSignature() call is unsuccessful
        signature = abi.encodePacked(r, s, uint8(0));
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);

        // ECDSA signature invalid (malleability protection).
        // ERC-1271 signature invalid as the signer is EOA and isValidSignature() call is unsuccessful
        signature = abi.encodePacked(r, uint256(0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A1), v);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);

        // ECDSA signature valid hence the transaction succeeds
        evc.setExpectedHash(bytes("0"));
        signature = abi.encodePacked(r, s, v);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);
        assertTrue(evc.fallbackCalled());
    }

    function test_RevertIfInvalidERC1271Signature_Permit(uint128 deadline, bytes calldata signature) public {
        address alice = address(new SignerERC1271(evc));
        SignerERC1271(alice).setSignatureHash(signature);

        vm.assume(!evc.haveCommonOwner(alice, address(0)));
        vm.warp(deadline);

        // ECDSA signature is always invalid here hence we fall back to ERC-1271 signature

        // ERC-1271 signature invalid due to the signer
        SignerERC1271(alice).setPermitHash(address(uint160(alice) + 1), address(this), 0, 0, deadline, 0, bytes("0"));
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);

        // ERC-1271 signature invalid due to the sender
        SignerERC1271(alice).setPermitHash(address(uint160(alice) + 1), address(0), 0, 0, deadline, 0, bytes("0"));
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);

        // ERC-1271 signature invalid due to the nonce namespace
        SignerERC1271(alice).setPermitHash(alice, address(this), 1, 0, deadline, 0, bytes("0"));
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);

        // ERC-1271 signature invalid due to the nonce
        SignerERC1271(alice).setPermitHash(alice, address(this), 0, 1, deadline, 0, bytes("0"));
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);

        // ERC-1271 signature invalid due to the deadline
        SignerERC1271(alice).setPermitHash(alice, address(this), 0, 0, uint256(deadline) + 1, 0, bytes("0"));
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);

        // ERC-1271 signature invalid due to the value
        SignerERC1271(alice).setPermitHash(alice, address(this), 0, 0, deadline, 1, bytes("0"));
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);

        // ERC-1271 signature invalid due to the data
        SignerERC1271(alice).setPermitHash(alice, address(this), 0, 0, deadline, 0, bytes("1"));
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);

        // ERC-1271 signature valid hence the transaction succeeds
        evc.setExpectedHash(bytes("0"));
        SignerERC1271(alice).setPermitHash(alice, address(this), 0, 0, deadline, 0, bytes("0"));
        evc.permit(alice, address(this), 0, 0, deadline, 0, bytes("0"), signature);
        assertTrue(evc.fallbackCalled());
    }

    function test_RevertIfInPermitDisabledMode_Permit(uint256 privateKey, uint128 value, bytes memory data) public {
        vm.assume(
            privateKey > 0
                && privateKey < 115792089237316195423570985008687907852837564279074904382605163141518161494337
        );
        data = abi.encode(keccak256(data));
        vm.deal(address(this), type(uint128).max);
        address alice = vm.addr(privateKey);

        evc.clearFallbackCalled();
        evc.setExpectedHash(data);
        evc.setExpectedValue(value);

        bytes19 addressPrefix = evc.getAddressPrefix(alice);
        vm.assume(alice != address(0) && alice != address(evc));

        signerECDSA.setPrivateKey(privateKey);
        bytes memory signature = signerECDSA.signPermit(alice, address(this), 0, 0, 1, value, data);

        // permit fails when in permit disabled mode
        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, true);

        vm.expectRevert(Errors.EVC_PermitDisabledMode.selector);
        evc.permit{value: value}(alice, address(this), 0, 0, 1, value, data, signature);

        // permit succeeds when not in permit disabled mode
        vm.prank(alice);
        evc.setPermitDisabledMode(addressPrefix, false);

        evc.permit{value: value}(alice, address(this), 0, 0, 1, value, data, signature);
        assertTrue(evc.fallbackCalled());
    }

    function test_Permit(uint256 privateKey) public {
        vm.assume(
            privateKey > 0
                && privateKey < 115792089237316195423570985008687907852837564279074904382605163141518161494337
        );
        address alice = vm.addr(privateKey);
        address bob = address(new SignerERC1271(evc));
        address target = address(new Vault(evc));

        vm.assume(!evc.haveCommonOwner(alice, address(0)) && !evc.haveCommonOwner(alice, bob));
        vm.deal(address(this), type(uint128).max);
        signerECDSA.setPrivateKey(privateKey);

        // encode a call that doesn't need authentication to prove it can be signed by anyone
        bytes memory data = abi.encodeWithSelector(IEVC.requireAccountStatusCheck.selector, address(0));

        // a call using ECDSA signature succeeds
        bytes memory signature = signerECDSA.signPermit(alice, address(this), 0, 0, block.timestamp, 0, data);
        evc.permit(alice, address(this), 0, 0, block.timestamp, 0, data, signature);

        // a call using ERC-1271 signature succeeds
        signature = bytes("bob's signature");
        SignerERC1271(bob).setSignatureHash(signature);
        SignerERC1271(bob).setPermitHash(bob, address(this), 0, 0, block.timestamp, 0, data);
        evc.permit(bob, address(this), 0, 0, block.timestamp, 0, data, signature);

        // encode a call that doesn't need authentication wrapped in a batch
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](1);
        items[0].targetContract = address(evc);
        items[0].onBehalfOfAccount = address(0);
        items[0].value = 0;
        items[0].data = data;
        data = abi.encodeWithSelector(IEVC.batch.selector, items);

        // a call using ECDSA signature succeeds
        signature = signerECDSA.signPermit(alice, address(this), 0, 1, block.timestamp, 0, data);
        evc.permit(alice, address(this), 0, 1, block.timestamp, 0, data, signature);

        // a call using ERC-1271 signature succeeds
        signature = bytes("bob's signature");
        SignerERC1271(bob).setSignatureHash(signature);
        SignerERC1271(bob).setPermitHash(bob, address(this), 0, 1, block.timestamp, 0, data);
        evc.permit(bob, address(this), 0, 1, block.timestamp, 0, data, signature);

        // encode a call that needs authentication to prove it cannot be signed by anyone
        data = abi.encodeWithSelector(IEVC.enableController.selector, bob, address(target));

        // a call using ECDSA signature fails because alice signed on behalf of bob
        signature = signerECDSA.signPermit(alice, address(this), 0, 2, block.timestamp, 0, data);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 2, block.timestamp, 0, data, signature);

        // a call using ERC1271 signature fails because bob signed on behalf of alice
        data = abi.encodeWithSelector(IEVC.enableController.selector, alice, address(target));
        signature = bytes("bob's signature");
        SignerERC1271(bob).setSignatureHash(signature);
        SignerERC1271(bob).setPermitHash(bob, address(this), 0, 2, block.timestamp, 0, data);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(bob, address(this), 0, 2, block.timestamp, 0, data, signature);

        // encode a call that needs authentication wrapped in a batch
        data = abi.encodeWithSelector(IEVC.enableController.selector, bob, address(target));
        items[0].targetContract = address(evc);
        items[0].onBehalfOfAccount = address(0);
        items[0].value = 0;
        items[0].data = data;
        data = abi.encodeWithSelector(IEVC.batch.selector, items);

        // a call using ECDSA signature fails because alice signed on behalf of bob
        signature = signerECDSA.signPermit(alice, address(this), 0, 2, block.timestamp, 0, data);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 2, block.timestamp, 0, data, signature);

        // a call using ERC1271 signature fails because bob signed on behalf of alice
        data = abi.encodeWithSelector(IEVC.enableController.selector, alice, address(target));
        items[0].targetContract = address(evc);
        items[0].onBehalfOfAccount = address(0);
        items[0].value = 0;
        items[0].data = data;
        data = abi.encodeWithSelector(IEVC.batch.selector, items);

        signature = bytes("bob's signature");
        SignerERC1271(bob).setSignatureHash(signature);
        SignerERC1271(bob).setPermitHash(bob, address(this), 0, 2, block.timestamp, 0, data);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(bob, address(this), 0, 2, block.timestamp, 0, data, signature);

        // encode a call that needs authentication
        data = abi.encodeWithSelector(IEVC.enableController.selector, alice, address(target));

        // a call using ECDSA signature succeeds because alice signed on behalf of herself
        signature = signerECDSA.signPermit(alice, address(this), 0, 2, block.timestamp, 0, data);
        evc.permit(alice, address(this), 0, 2, block.timestamp, 0, data, signature);

        // a call using ERC1271 signature succeeds because bob signed on behalf of himself
        data = abi.encodeWithSelector(IEVC.enableController.selector, bob, address(target));

        signature = bytes("bob's signature");
        SignerERC1271(bob).setSignatureHash(signature);
        SignerERC1271(bob).setPermitHash(bob, address(this), 0, 2, block.timestamp, 0, data);
        evc.permit(bob, address(this), 0, 2, block.timestamp, 0, data, signature);

        // encode a call that needs authentication wrapped in a batch
        data = abi.encodeWithSelector(IEVC.enableController.selector, alice, address(target));
        items[0].targetContract = address(evc);
        items[0].onBehalfOfAccount = address(0);
        items[0].value = 0;
        items[0].data = data;
        data = abi.encodeWithSelector(IEVC.batch.selector, items);

        // a call using ECDSA signature succeeds because alice signed on behalf of herself
        signature = signerECDSA.signPermit(alice, address(this), 0, 3, block.timestamp, 0, data);
        evc.permit(alice, address(this), 0, 3, block.timestamp, 0, data, signature);

        // a call using ERC1271 signature succeeds because bob signed on behalf of himself
        data = abi.encodeWithSelector(IEVC.enableController.selector, bob, address(target));
        items[0].targetContract = address(evc);
        items[0].onBehalfOfAccount = address(0);
        items[0].value = 0;
        items[0].data = data;
        data = abi.encodeWithSelector(IEVC.batch.selector, items);

        signature = bytes("bob's signature");
        SignerERC1271(bob).setSignatureHash(signature);
        SignerERC1271(bob).setPermitHash(bob, address(this), 0, 3, block.timestamp, 0, data);
        evc.permit(bob, address(this), 0, 3, block.timestamp, 0, data, signature);

        // encode a call to an external target contract
        data = abi.encodeWithSelector(
            IEVC.call.selector,
            target,
            bob,
            123,
            abi.encodeWithSelector(Target.callTest.selector, address(evc), address(evc), 123, bob, false)
        );

        // a call using ECDSA signature fails because alice signed on behalf of bob
        signature = signerECDSA.signPermit(alice, address(this), 0, 4, block.timestamp, type(uint256).max, data);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit{value: 123}(alice, address(this), 0, 4, block.timestamp, type(uint256).max, data, signature);

        // a call using ERC1271 signature fails because bob signed on behalf of alice
        data = abi.encodeWithSelector(
            IEVC.call.selector,
            target,
            alice,
            123,
            abi.encodeWithSelector(Target.callTest.selector, address(evc), address(evc), 123, alice, false)
        );

        signature = bytes("bob's signature");
        SignerERC1271(bob).setSignatureHash(signature);
        SignerERC1271(bob).setPermitHash(bob, address(this), 0, 4, block.timestamp, type(uint256).max, data);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit{value: 123}(bob, address(this), 0, 4, block.timestamp, type(uint256).max, data, signature);

        // encode a call to an external target contract wrapped in a batch
        data = abi.encodeWithSelector(Target.callTest.selector, address(evc), address(evc), 123, bob, false);
        items[0].targetContract = target;
        items[0].onBehalfOfAccount = bob;
        items[0].value = 123;
        items[0].data = data;
        data = abi.encodeWithSelector(IEVC.batch.selector, items);

        // a call using ECDSA signature fails because alice signed on behalf of bob
        signature = signerECDSA.signPermit(alice, address(this), 0, 4, block.timestamp, type(uint256).max, data);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit{value: 123}(alice, address(this), 0, 4, block.timestamp, type(uint256).max, data, signature);

        // a call using ERC1271 signature fails because bob signed on behalf of alice
        data = abi.encodeWithSelector(Target.callTest.selector, address(evc), address(evc), 123, alice, false);
        items[0].targetContract = target;
        items[0].onBehalfOfAccount = alice;
        items[0].value = 123;
        items[0].data = data;
        data = abi.encodeWithSelector(IEVC.batch.selector, items);

        signature = bytes("bob's signature");
        SignerERC1271(bob).setSignatureHash(signature);
        SignerERC1271(bob).setPermitHash(bob, address(this), 0, 4, block.timestamp, type(uint256).max, data);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit{value: 123}(bob, address(this), 0, 4, block.timestamp, type(uint256).max, data, signature);

        // encode a call to an external target contract
        data = abi.encodeWithSelector(
            IEVC.call.selector,
            target,
            alice,
            123,
            abi.encodeWithSelector(Target.callTest.selector, address(evc), address(evc), 123, alice, false)
        );

        // a call using ECDSA signature succeeds because alice signed on behalf of herself
        signature = signerECDSA.signPermit(alice, address(this), 0, 4, block.timestamp, type(uint256).max, data);
        vm.expectEmit(true, true, true, true, address(evc));
        emit CallWithContext(address(this), evc.getAddressPrefix(alice), alice, address(evc), bytes4(data));
        vm.expectEmit(true, true, true, true, address(evc));
        emit CallWithContext(alice, evc.getAddressPrefix(alice), alice, target, Target.callTest.selector);
        evc.permit{value: 123}(alice, address(this), 0, 4, block.timestamp, type(uint256).max, data, signature);

        // a call using ERC1271 signature succeeds because bob signed on behalf of himself
        data = abi.encodeWithSelector(
            IEVC.call.selector,
            target,
            bob,
            123,
            abi.encodeWithSelector(Target.callTest.selector, address(evc), address(evc), 123, bob, false)
        );

        signature = bytes("bob's signature");
        SignerERC1271(bob).setSignatureHash(signature);
        SignerERC1271(bob).setPermitHash(bob, address(this), 0, 4, block.timestamp, type(uint256).max, data);
        emit CallWithContext(address(this), evc.getAddressPrefix(bob), bob, address(evc), bytes4(data));
        vm.expectEmit(true, true, true, true, address(evc));
        emit CallWithContext(bob, evc.getAddressPrefix(bob), bob, target, Target.callTest.selector);
        evc.permit{value: 123}(bob, address(this), 0, 4, block.timestamp, type(uint256).max, data, signature);

        // encode a call to an external target contract wrapped in a batch
        data = abi.encodeWithSelector(Target.callTest.selector, address(evc), address(evc), 456, alice, false);
        items[0].targetContract = target;
        items[0].onBehalfOfAccount = alice;
        items[0].value = 456;
        items[0].data = data;
        data = abi.encodeWithSelector(IEVC.batch.selector, items);

        // a call using ECDSA signature succeeds because alice signed on behalf of herself
        signature = signerECDSA.signPermit(alice, address(this), 0, 5, block.timestamp, 456, data);
        vm.expectEmit(true, true, true, true, address(evc));
        emit CallWithContext(address(this), evc.getAddressPrefix(alice), alice, address(evc), bytes4(data));
        vm.expectEmit(true, true, true, true, address(evc));
        emit CallWithContext(alice, evc.getAddressPrefix(alice), alice, target, Target.callTest.selector);
        evc.permit{value: 456}(alice, address(this), 0, 5, block.timestamp, 456, data, signature);

        // a call using ERC1271 signature succeeds because bob signed on behalf of himself
        data = abi.encodeWithSelector(Target.callTest.selector, address(evc), address(evc), 456, bob, false);
        items[0].targetContract = target;
        items[0].onBehalfOfAccount = bob;
        items[0].value = 456;
        items[0].data = data;
        data = abi.encodeWithSelector(IEVC.batch.selector, items);

        signature = bytes("bob's signature");
        SignerERC1271(bob).setSignatureHash(signature);
        SignerERC1271(bob).setPermitHash(bob, address(this), 0, 5, block.timestamp, 456, data);
        emit CallWithContext(address(this), evc.getAddressPrefix(bob), bob, address(evc), bytes4(data));
        vm.expectEmit(true, true, true, true, address(evc));
        emit CallWithContext(bob, evc.getAddressPrefix(bob), bob, target, Target.callTest.selector);
        evc.permit{value: 456}(bob, address(this), 0, 5, block.timestamp, 456, data, signature);
    }

    function test_SetOperator_Permit(uint256 privateKey, uint8 subAccountId1, uint8 subAccountId2) public {
        vm.assume(
            privateKey > 0
                && privateKey < 115792089237316195423570985008687907852837564279074904382605163141518161494335
        );
        address alice = vm.addr(privateKey);
        address bob = address(new SignerERC1271(evc));
        bytes19 addressPrefixAlice = evc.getAddressPrefix(alice);
        bytes19 addressPrefixBob = evc.getAddressPrefix(bob);
        address operator = vm.addr(privateKey + 1);
        address otherOperator = vm.addr(privateKey + 2);

        vm.assume(alice != address(0) && bob != address(0));
        vm.assume(operator != address(0) && operator != address(evc));
        vm.assume(
            !evc.haveCommonOwner(alice, operator) && !evc.haveCommonOwner(bob, operator)
                && !evc.haveCommonOwner(alice, bob)
        );
        vm.assume(subAccountId1 > 0 && subAccountId2 > 0 && subAccountId1 != subAccountId2);
        signerECDSA.setPrivateKey(privateKey);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](3);

        // encode the setAccountOperator to prove that it's possible to set an operator
        // on behalf of the signer or their accounts
        // alice
        items[0].targetContract = address(evc);
        items[0].onBehalfOfAccount = address(0);
        items[0].value = 0;
        items[0].data = abi.encodeWithSelector(IEVC.setAccountOperator.selector, alice, operator, true);
        items[1].targetContract = address(evc);
        items[1].onBehalfOfAccount = address(0);
        items[1].value = 0;
        items[1].data = abi.encodeWithSelector(
            IEVC.setAccountOperator.selector, address(uint160(alice) ^ subAccountId1), operator, true
        );
        items[2].targetContract = address(evc);
        items[2].onBehalfOfAccount = address(0);
        items[2].value = 0;
        items[2].data = abi.encodeWithSelector(
            IEVC.setOperator.selector,
            addressPrefixAlice,
            operator,
            (1 << 0) | (1 << subAccountId1) | (1 << subAccountId2)
        );
        bytes memory data = abi.encodeWithSelector(IEVC.batch.selector, items);

        // a call using ECDSA signature succeeds
        bytes memory signature = signerECDSA.signPermit(alice, address(this), 0, 0, block.timestamp, 0, data);
        evc.permit(alice, address(this), 0, 0, block.timestamp, 0, data, signature);
        assertEq(evc.isAccountOperatorAuthorized(alice, operator), true);
        assertEq(evc.isAccountOperatorAuthorized(address(uint160(alice) ^ subAccountId1), operator), true);
        assertEq(evc.isAccountOperatorAuthorized(address(uint160(alice) ^ subAccountId2), operator), true);
        assertEq(evc.getOperator(addressPrefixAlice, operator), (1 << 0) | (1 << subAccountId1) | (1 << subAccountId2));

        // a call using ERC-1271 signature succeeds
        // bob
        items[0].data = abi.encodeWithSelector(IEVC.setAccountOperator.selector, bob, operator, true);
        items[1].data = abi.encodeWithSelector(
            IEVC.setAccountOperator.selector, address(uint160(bob) ^ subAccountId1), operator, true
        );
        items[2].data = abi.encodeWithSelector(
            IEVC.setOperator.selector,
            addressPrefixBob,
            operator,
            (1 << 0) | (1 << subAccountId1) | (1 << subAccountId2)
        );
        data = abi.encodeWithSelector(IEVC.batch.selector, items);

        signature = bytes("bob's signature");
        SignerERC1271(bob).setSignatureHash(signature);
        SignerERC1271(bob).setPermitHash(bob, address(this), 0, 0, block.timestamp, 0, data);
        evc.permit(bob, address(this), 0, 0, block.timestamp, 0, data, signature);
        assertEq(evc.isAccountOperatorAuthorized(bob, operator), true);
        assertEq(evc.isAccountOperatorAuthorized(address(uint160(bob) ^ subAccountId1), operator), true);
        assertEq(evc.isAccountOperatorAuthorized(address(uint160(bob) ^ subAccountId2), operator), true);
        assertEq(evc.getOperator(addressPrefixBob, operator), (1 << 0) | (1 << subAccountId1) | (1 << subAccountId2));

        // if the operator tries to authorize some other operator directly, it's not possible
        // alice
        vm.prank(operator);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setOperator(addressPrefixAlice, operator, 0);

        vm.prank(operator);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setOperator(addressPrefixAlice, otherOperator, 0);

        vm.prank(operator);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setAccountOperator(alice, otherOperator, true);

        // bob
        vm.prank(operator);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setOperator(addressPrefixBob, operator, 0);

        vm.prank(operator);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setOperator(addressPrefixBob, otherOperator, 0);

        vm.prank(operator);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.setAccountOperator(bob, otherOperator, true);

        // but it succeeds if it's done using the signed data
        // alice
        data = abi.encodeWithSelector(IEVC.setOperator.selector, addressPrefixAlice, otherOperator, 2);

        signature = signerECDSA.signPermit(alice, operator, 0, 1, block.timestamp, 0, data);
        vm.prank(operator);
        evc.permit(alice, operator, 0, 1, block.timestamp, 0, data, signature);
        assertEq(evc.isAccountOperatorAuthorized(address(uint160(alice) ^ 1), otherOperator), true);

        data = abi.encodeWithSelector(IEVC.setAccountOperator.selector, alice, otherOperator, true);

        signature = signerECDSA.signPermit(alice, operator, 0, 2, block.timestamp, 0, data);
        vm.prank(operator);
        evc.permit(alice, operator, 0, 2, block.timestamp, 0, data, signature);
        assertEq(evc.isAccountOperatorAuthorized(alice, otherOperator), true);

        // bob
        data = abi.encodeWithSelector(IEVC.setOperator.selector, addressPrefixBob, otherOperator, 2);

        signature = bytes("bob's signature");
        SignerERC1271(bob).setSignatureHash(signature);
        SignerERC1271(bob).setPermitHash(bob, operator, 0, 1, block.timestamp, 0, data);

        vm.prank(operator);
        evc.permit(bob, operator, 0, 1, block.timestamp, 0, data, signature);
        assertEq(evc.isAccountOperatorAuthorized(address(uint160(bob) ^ 1), otherOperator), true);

        data = abi.encodeWithSelector(IEVC.setAccountOperator.selector, bob, otherOperator, true);
        signature = bytes("bob's signature");
        SignerERC1271(bob).setSignatureHash(signature);
        SignerERC1271(bob).setPermitHash(bob, operator, 0, 2, block.timestamp, 0, data);

        vm.prank(operator);
        evc.permit(bob, operator, 0, 2, block.timestamp, 0, data, signature);
        assertEq(evc.isAccountOperatorAuthorized(bob, otherOperator), true);

        // when the operator is authorized, it can sign permit messages on behalf of the authorized account
        // alice
        signerECDSA.setPrivateKey(privateKey + 1);

        data = abi.encodeWithSelector(IEVC.enableCollateral.selector, alice, address(0));

        signature = signerECDSA.signPermit(operator, address(this), 0, 0, block.timestamp, 0, data);
        evc.permit(operator, address(this), 0, 0, block.timestamp, 0, data, signature);
        assertEq(evc.isCollateralEnabled(alice, address(0)), true);

        // bob
        data = abi.encodeWithSelector(IEVC.enableCollateral.selector, bob, address(0));

        signature = signerECDSA.signPermit(operator, address(this), 0, 1, block.timestamp, 0, data);
        evc.permit(operator, address(this), 0, 1, block.timestamp, 0, data, signature);
        assertEq(evc.isCollateralEnabled(bob, address(0)), true);

        // and another one
        // alice
        data = abi.encodeWithSelector(Target.callTest.selector, address(evc), address(evc), 0, alice, true);

        signature = signerECDSA.signPermit(operator, address(this), 0, 2, block.timestamp, 0, data);
        evc.permit(operator, address(this), 0, 2, block.timestamp, 0, data, signature);

        // bob
        data = abi.encodeWithSelector(Target.callTest.selector, address(evc), address(evc), 0, bob, true);

        signature = signerECDSA.signPermit(operator, address(this), 0, 3, block.timestamp, 0, data);
        evc.permit(operator, address(this), 0, 3, block.timestamp, 0, data, signature);

        // but it cannot execute a signed permit messages on behalf of other accounts for which it's not authorized
        // alice
        vm.prank(operator);
        evc.setAccountOperator(address(uint160(alice) ^ subAccountId1), operator, false);

        data =
            abi.encodeWithSelector(IEVC.enableCollateral.selector, address(uint160(alice) ^ subAccountId1), address(0));

        signature = signerECDSA.signPermit(operator, address(this), 0, 4, block.timestamp, 0, data);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(operator, address(this), 0, 4, block.timestamp, 0, data, signature);

        // bob
        vm.prank(operator);
        evc.setAccountOperator(address(uint160(bob) ^ subAccountId1), operator, false);

        data = abi.encodeWithSelector(IEVC.enableCollateral.selector, address(uint160(bob) ^ subAccountId1), address(0));

        signature = signerECDSA.signPermit(operator, address(this), 0, 4, block.timestamp, 0, data);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(operator, address(this), 0, 4, block.timestamp, 0, data, signature);

        // also, it cannot execute a signed permit messages to set other operators, even for accounts for which it's
        // authorized
        // alice
        assertEq(evc.isAccountOperatorAuthorized(alice, otherOperator), true);

        data = abi.encodeWithSelector(IEVC.setAccountOperator.selector, alice, otherOperator, false);

        signature = signerECDSA.signPermit(operator, address(this), 0, 4, block.timestamp, 0, data);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(operator, address(this), 0, 4, block.timestamp, 0, data, signature);

        vm.prank(alice);
        evc.setAccountOperator(alice, otherOperator, false);

        data = abi.encodeWithSelector(IEVC.setAccountOperator.selector, alice, otherOperator, true);

        signature = signerECDSA.signPermit(operator, address(this), 0, 4, block.timestamp, 0, data);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(operator, address(this), 0, 4, block.timestamp, 0, data, signature);

        // bob
        assertEq(evc.isAccountOperatorAuthorized(bob, otherOperator), true);

        data = abi.encodeWithSelector(IEVC.setAccountOperator.selector, bob, otherOperator, false);

        signature = signerECDSA.signPermit(operator, address(this), 0, 4, block.timestamp, 0, data);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(operator, address(this), 0, 4, block.timestamp, 0, data, signature);

        vm.prank(bob);
        evc.setAccountOperator(bob, otherOperator, false);

        data = abi.encodeWithSelector(IEVC.setAccountOperator.selector, bob, otherOperator, true);

        signature = signerECDSA.signPermit(operator, address(this), 0, 4, block.timestamp, 0, data);
        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(operator, address(this), 0, 4, block.timestamp, 0, data, signature);

        // but it can execute a signed permit message to deauthorize itself
        // alice
        data = abi.encodeWithSelector(IEVC.setAccountOperator.selector, alice, operator, false);

        signature = signerECDSA.signPermit(operator, address(this), 0, 4, block.timestamp, 0, data);
        evc.permit(operator, address(this), 0, 4, block.timestamp, 0, data, signature);
        assertEq(evc.isAccountOperatorAuthorized(alice, operator), false);

        // bob
        data = abi.encodeWithSelector(IEVC.setAccountOperator.selector, bob, operator, false);

        signature = signerECDSA.signPermit(operator, address(this), 0, 5, block.timestamp, 0, data);
        evc.permit(operator, address(this), 0, 5, block.timestamp, 0, data, signature);
        assertEq(evc.isAccountOperatorAuthorized(bob, operator), false);
    }

    function test_RevertIfInPermit_SetLockdownMode(uint256 privateKey) public {
        vm.assume(
            privateKey > 0
                && privateKey < 115792089237316195423570985008687907852837564279074904382605163141518161494337
        );
        address alice = vm.addr(privateKey);

        bytes19 addressPrefix = evc.getAddressPrefix(alice);
        vm.assume(alice != address(0) && alice != address(evc));

        signerECDSA.setPrivateKey(privateKey);

        bytes memory data = abi.encodeWithSelector(IEVC.setLockdownMode.selector, addressPrefix, true);
        bytes memory signature = signerECDSA.signPermit(alice, address(this), 0, 0, 1, 0, data);

        // succeeds in permit when enabling
        evc.permit(alice, address(this), 0, 0, 1, 0, data, signature);
        assertEq(evc.isLockdownMode(addressPrefix), true);

        // fails in permit when disabling
        data = abi.encodeWithSelector(IEVC.setLockdownMode.selector, addressPrefix, false);
        signature = signerECDSA.signPermit(alice, address(this), 0, 1, 1, 0, data);

        vm.expectRevert(Errors.EVC_NotAuthorized.selector);
        evc.permit(alice, address(this), 0, 1, 1, 0, data, signature);
    }

    function test_RevertIfInPermit_SetPermitDisabledMode(uint256 privateKey) public {
        vm.assume(
            privateKey > 0
                && privateKey < 115792089237316195423570985008687907852837564279074904382605163141518161494337
        );
        address alice = vm.addr(privateKey);

        bytes19 addressPrefix = evc.getAddressPrefix(alice);
        vm.assume(alice != address(0) && alice != address(evc));

        signerECDSA.setPrivateKey(privateKey);

        bytes memory data = abi.encodeWithSelector(IEVC.setPermitDisabledMode.selector, addressPrefix, true);
        bytes memory signature = signerECDSA.signPermit(alice, address(this), 0, 0, 1, 0, data);

        // succeeds in permit when enabling
        evc.permit(alice, address(this), 0, 0, 1, 0, data, signature);
        assertEq(evc.isPermitDisabledMode(addressPrefix), true);

        // fails in permit when disabling
        data = abi.encodeWithSelector(IEVC.setPermitDisabledMode.selector, addressPrefix, false);
        signature = signerECDSA.signPermit(alice, address(this), 0, 1, 1, 0, data);

        vm.expectRevert(Errors.EVC_PermitDisabledMode.selector);
        evc.permit(alice, address(this), 0, 1, 1, 0, data, signature);
    }
}
