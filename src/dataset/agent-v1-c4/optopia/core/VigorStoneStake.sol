// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "../dependencies/EnumerableApply.sol";

contract VigorStoneStake is ERC1155Holder {
	using EnumerableMap for EnumerableMap.AddressToUintMap;
	using EnumerableApply for EnumerableApply.UintToApply;

	uint256 public constant TOKENID = 0;
	uint64 public immutable LOCKTIME = 7 days;
	IERC1155 public immutable TOKEN;
	uint256 public immutable MAXSTAKE = 5;

	EnumerableMap.AddressToUintMap internal stakes;

	mapping(address => uint256) internal applyIds;

	mapping(address => EnumerableApply.UintToApply) internal applies;

	event Staked(address account, uint256 amount);

	event ApplyUnstaked(address account, uint256 applyId, uint256 amount, uint256 applyTime);

	event Unstaked(address account, uint256 applyId, uint256 amount);

	constructor(IERC1155 _token) {
		TOKEN = _token;
	}

	function stake(uint256 amount) external {
		require(getStake(msg.sender) + amount <= MAXSTAKE, "stake exceeds max stake");
		require(amount > 0, "amount must be greater than 0");
		TOKEN.safeTransferFrom(msg.sender, address(this), TOKENID, amount, "");
		uint256 oldAmount = getStake(msg.sender);
		stakes.set(msg.sender, oldAmount + amount);
		emit Staked(msg.sender, amount);
	}

	function applyUnstake(uint256 amount) external {
		require(amount > 0, "amount must be greater than 0");
		uint256 oldAmount = getStake(msg.sender);
		require(amount <= oldAmount, "amount must be less than or equal to stakes");
		uint256 id = applyIds[msg.sender];
		uint256 newStake = oldAmount - amount;
		if (newStake == 0) {
			stakes.remove(msg.sender);
		} else {
			stakes.set(msg.sender, newStake);
		}
		applies[msg.sender].set(id, EnumerableApply.ApplyInfo(amount, block.timestamp));
		applyIds[msg.sender]++;
		emit ApplyUnstaked(msg.sender, id, amount, block.timestamp);
	}

	function unstake(address to, uint256 applyId) external {
		require(applies[msg.sender].contains(applyId), "nonexistent apply");
		EnumerableApply.ApplyInfo memory info = getApply(msg.sender, applyId);
		require(info.applyTime + LOCKTIME <= block.timestamp, "unstake locktime not expired");
		TOKEN.safeTransferFrom(address(this), to, TOKENID, info.amount, "");
		applies[msg.sender].remove(applyId);
		emit Unstaked(msg.sender, applyId, info.amount);
	}

	function getStake(address account) public view returns (uint256) {
		if (!stakes.contains(account)) {
			return 0;
		}
		return stakes.get(account);
	}

	function getApply(address account, uint256 applyId) public view returns (EnumerableApply.ApplyInfo memory info) {
		return applies[account].get(applyId);
	}

	function stakesOf(uint256 start, uint256 amount) public view returns (address[] memory stakers, uint256[] memory amounts) {
		uint256 size = stakeLength();
		if (size != 0 && start < size) {
			if (start + amount > size) {
				amount = size - start;
			}
			stakers = new address[](amount);
			amounts = new uint256[](amount);
			for (uint256 i = 0; i < amount; i++) {
				(stakers[i], amounts[i]) = stakes.at(start + i);
			}
		}
	}

	function stakeLength() public view returns (uint256) {
		return stakes.length();
	}

	function applyLength(address account) public view returns (uint256) {
		return applies[account].length();
	}

	function applyOf(address account, uint256 start, uint256 amount) public view returns (uint256[] memory ids, EnumerableApply.ApplyInfo[] memory infos) {
		uint256 size = applyLength(account);
		if (size != 0) {
			if (start < size) {
				if (start + amount > size) {
					amount = size - start;
				}
				ids = new uint256[](amount);
				infos = new EnumerableApply.ApplyInfo[](amount);
				for (uint256 i = 0; i < amount; i++) {
					(ids[i], infos[i]) = applies[account].at(start + i);
				}
			}
		}
	}
}
