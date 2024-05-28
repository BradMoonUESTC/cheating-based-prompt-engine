// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./OPAIStake.sol";
import "./VigorStoneStake.sol";
import "./VigorStone.sol";

contract Helpers {
	uint256 public constant TOKENID = 0;
	VigorStoneStake public vigorStoneStake;
	VigorStone public vigorStone;
	OPAIStake public opaiStake;
	IERC20 public opai;

	struct VigorStoneInfo {
		uint256 totalSupply;
		uint256 maxSupply;
		uint256 price;
	}

	struct State {
		uint256 vigorStoneBalance;
		uint256 vigorStoneStake;
		uint256 vigorStoneApplyLength;
		uint256 opaiBalance;
		uint256 opaiStake;
		uint256 opaiApplyLength;
		VigorStoneInfo vigorStoneInfo;
	}

	constructor(VigorStoneStake _vigorStoneStake, VigorStone _vigorStone, OPAIStake _opaiStake, IERC20 _opai) {
		vigorStoneStake = _vigorStoneStake;
		vigorStone = _vigorStone;
		opaiStake = _opaiStake;
		opai = _opai;
	}

	function stateOf(address account) public view returns(State memory state) {
		state.vigorStoneBalance = vigorStone.balanceOf(account, TOKENID);
		state.vigorStoneStake = vigorStoneStake.getStake(account);
		state.vigorStoneApplyLength = vigorStoneStake.applyLength(account);
		state.opaiStake = opaiStake.getStake(account);
		state.opaiApplyLength = opaiStake.applyLength(account);
		state.opaiBalance = opai.balanceOf(account);
		state.vigorStoneInfo.maxSupply = vigorStone.maxSupply();
		state.vigorStoneInfo.price = vigorStone.price();
		state.vigorStoneInfo.totalSupply = vigorStone.totalSupply(TOKENID);
	}

	function vigoreStoneApplyList(address account, uint256 start, uint256 amount) public view returns(uint256[] memory ids, EnumerableApply.ApplyInfo[] memory infos) {
		return vigorStoneStake.applyOf(account, start, amount);
	}

	function opaiApplyList(address account, uint256 start, uint256 amount) public view returns(uint256[] memory ids, EnumerableApply.ApplyInfo[] memory infos) {
		return opaiStake.applyOf(account, start, amount);
	}
}