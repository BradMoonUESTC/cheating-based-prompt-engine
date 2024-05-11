// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Controller.sol";

contract ETHDeliver is Controller, EIP712 {

	/// @dev keccak256("DepositorWithdrawal(bytes32 logHash,address depositor,uint256 amount)")
	bytes32 public DepositorWithdrawalTypesHash = keccak256("DepositorWithdrawal(bytes32 logHash,address depositor,uint256 amount)");

	/// @dev keccak256(abi.encodePacked(txHash,logIndex))
	mapping(bytes32 => bool) public finalizedTxs;

	/// @dev keccak256(abi.encodePacked(txHash,logIndex))
	mapping(bytes32 => bool) public depositorWithdrawals;

	/// @dev emit when user deposits
	event Deposit(uint256 srcChainId, uint256 dstChainId, address from, address to, uint256 amount, uint256 fee, uint32 timeoutAt);

	/// @dev emit when user withdraws
	event DepositorWithdrawn(DepositorWithdrawal w);

	/// @dev emit when a deposit finalized
	event Finalize(address relayer, uint256 srcChainId, uint256 dstChainId, bytes32 logHash, address to, uint256 amount, uint256 fee);

	/// @dev emit when admin withdrawn
	event EmergencyWithdraw(address admin, address to, IERC20 token, uint256 amount);

	struct DepositorWithdrawal {
		bytes32 logHash; // mark the deposit transaction
		address depositor;
		uint256 amount;
		bytes depositorSig;
		bytes guardianSig;
	}

	struct FinalizeTxMeta {
		uint256 srcChainId;
		bytes32 logHash; // mark the deposit transaction
		address to;
		uint256 amount;
		uint32 timeoutAt;
	}

	modifier ensureDepositorWithdraw(bytes32 logHash) {
		require(!depositorWithdrawals[logHash], "deposits already withdraw");
		depositorWithdrawals[logHash] = true;
		_;
	}

	modifier ensureFinalized(bytes32 logHash) {
		require(!finalizedTxs[logHash], "tx finalized");
		finalizedTxs[logHash] = true;
		_;
	}

	modifier notTimeout(uint32 timeoutAt) {
		require(block.timestamp <= timeoutAt, "expired");
		_;
	}

	constructor(ICore _core, Config_ memory config) Controller(_core, config) EIP712("ETHDELIVER", "v1") {
	}

	// if deposit using contract, please implement https://eips.ethereum.org/EIPS/eip-1271, in case withdraw failed
	function deposit(address to, uint256 dstChainId, uint32 timeoutAt) external payable notTimeout(timeoutAt) wherNotPaused {
		uint256 value = msg.value;
		uint256 fee = depositFee(value);
		require(value >= fee, "insufficient value for deposit fee");
		value -= fee;
		_transfer(owner(), fee);
		emit Deposit(chainId(), dstChainId, msg.sender, to, value, fee, timeoutAt);
	}

	function mulFinalize(FinalizeTxMeta[] memory metas) external onlyRelayer {
		for (uint256 i = 0; i < metas.length; i++) {
			FinalizeTxMeta memory meta = metas[i];
			require(!finalizedTxs[meta.logHash], "tx finalized");
			finalizedTxs[meta.logHash] = true;
			_finalize(meta.srcChainId, meta.logHash, meta.to, meta.amount);
		}
	}

	function finalize(FinalizeTxMeta memory meta) external ensureFinalized(meta.logHash) notTimeout(meta.timeoutAt) onlyRelayer wherNotPaused {
		_finalize(meta.srcChainId, meta.logHash, meta.to, meta.amount);
	}

	function _finalize(uint256 srcChainId, bytes32 logHash, address to, uint256 amount) internal {
		uint256 fee = finalizeTxGasFee();
		require(amount >= fee, "insufficient amount for finalize fee");
		amount -= fee;
		_transfer(to, amount);
		_transfer(msg.sender, fee);
		emit Finalize(msg.sender, srcChainId, chainId(), logHash, to, amount, fee);
	}

	function depositFee(uint256 amount) public view returns(uint256) {
		return config.depositBaseFee + (amount * config.depositFeeRate / MAXPCT);
	}

	function finalizeTxGasFee() public view returns (uint256) {
	    return config.finalizeTxGas * gasPrice();
	}

	function _transfer(address to, uint256 value) internal {
		(bool success, ) = to.call{ value: value }("");
		require(success, "transfer failed");
	}

	function depositorWithdraw(DepositorWithdrawal memory w) external ensureDepositorWithdraw(w.logHash) wherNotPaused {
		bytes32 hash = hashTypedDataV4ForDepositorWithdraw(w.logHash, w.depositor, w.amount);
		require(SignatureChecker.isValidSignatureNow(w.depositor, hash, w.depositorSig), "signer is not depositor");
		require(SignatureChecker.isValidSignatureNow(guardian(), hash, w.guardianSig), "signer not guardian");
		_transfer(w.depositor, w.amount);
		emit DepositorWithdrawn(w);
	}

	function hashTypedDataV4ForDepositorWithdraw(
		bytes32 logHash,
		address depositor,
		uint256 amount
	) public view returns (bytes32) {
		return _hashTypedDataV4(keccak256(abi.encode(DepositorWithdrawalTypesHash, logHash, depositor, amount)));
	}

	function emergencyWithdraw(IERC20 token, address to, uint256 amount) external onlyOwner {
		if (address(token) == address(0)) {
			(bool success, ) = to.call{ value: amount }("");
			require(success, "withdraw eth failed");
		} else {
			token.transfer(to, amount);
		}
		emit EmergencyWithdraw(msg.sender, to, token, amount);
	}

	function chainId() public view returns (uint256 id) {
		assembly {
			id := chainid()
		}
	}

	function gasPrice() public view returns (uint256 price) {
		assembly {
			price := gasprice()
		}
	}

	receive() external payable {}
}
