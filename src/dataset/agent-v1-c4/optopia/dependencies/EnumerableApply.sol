// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

library EnumerableApply {
	using EnumerableSet for EnumerableSet.Bytes32Set;
	error EnumerableMapNonexistentKey(uint256 key);

	struct ApplyInfo {
		uint256 amount;
		uint256 applyTime;
	}

	struct UintToApply {
		EnumerableSet.Bytes32Set _keys;
		mapping(uint256 => ApplyInfo) _values;
	}

	function set(UintToApply storage map, uint256 key, ApplyInfo memory value) internal returns (bool) {
		map._values[key] = value;
		return map._keys.add(bytes32(key));
	}

	function remove(UintToApply storage map, uint256 key) internal returns (bool) {
		delete map._values[key];
		return map._keys.remove(bytes32(key));
	}

	function contains(UintToApply storage map, uint256 key) internal view returns (bool) {
		return map._keys.contains(bytes32(key));
	}

	function length(UintToApply storage map) internal view returns (uint256) {
		return map._keys.length();
	}

	function at(UintToApply storage map, uint256 index) internal view returns (uint256, ApplyInfo memory) {
		bytes32 key = map._keys.at(index);
		return (uint256(key), map._values[uint256(key)]);
	}

	function tryGet(UintToApply storage map, uint256 key) internal view returns (bool, ApplyInfo memory) {
		ApplyInfo memory value = map._values[key];
		if (value.applyTime == 0) {
			return (contains(map, key), ApplyInfo({ amount: 0, applyTime: 0 }));
		} else {
			return (true, value);
		}
	}

	function get(UintToApply storage map, uint256 key) internal view returns (ApplyInfo memory) {
		ApplyInfo memory value = map._values[key];
		if (value.applyTime == 0 && !contains(map, key)) {
			revert EnumerableMapNonexistentKey(key);
		}
		return value;
	}

	function keys(UintToApply storage map) internal view returns (bytes32[] memory) {
		return map._keys.values();
	}
}
