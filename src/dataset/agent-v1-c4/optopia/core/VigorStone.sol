// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";

contract VigorStone is ERC1155SupplyUpgradeable, ERC1155BurnableUpgradeable, Ownable2StepUpgradeable {
	uint256 public constant TOKENID = 0;
	uint256 public maxSupply;
	uint256 public price;
	string public tokenURI;

	error InvalidMaxSupply(uint256 amount);
	error InvalidPrice(uint256 price);
	error InsufficientValue(uint256 required, uint256 available);
	error MaxSupplyExceeds(uint256 maxSupply, uint256 totalSupply, uint256 amount);

	event MaxSupplyUpdated(uint256 maxSupply);
	event PriceUpdated(uint256 price);

	function initialize(address owner) external initializer {
		_transferOwnership(owner);
		__ERC1155_init("Vigor Stone");
	}

	function init(uint256 _maxSupply, uint256 _price) external onlyOwner {
		_setMaxSupply(_maxSupply);
		_setPrice(_price);
	}

	function setMaxSupply(uint256 amount) external onlyOwner {
		_setMaxSupply(amount);
	}

	function _setMaxSupply(uint256 amount) internal {
		if (amount <= totalSupply(TOKENID)) {
			revert InvalidMaxSupply(amount);
		}
		maxSupply = amount;
		emit MaxSupplyUpdated(amount);
	}

	function setPrice(uint256 _price) external onlyOwner {
		_setPrice(_price);
	}

	function _setPrice(uint256 _price) internal  {
		if (_price == 0) {
			revert InvalidPrice(_price);
		}
		price = _price;
		emit PriceUpdated(_price);
	}

	function mint(address to, uint256 amount) external payable {
		if (totalSupply(TOKENID) + amount > maxSupply) {
			revert MaxSupplyExceeds(maxSupply, totalSupply(TOKENID), amount);
		}
		if (price == 0) {
			revert InvalidPrice(price);
		}
		uint256 totalValue = amount * price;
		if (msg.value < totalValue) {
			revert InsufficientValue(totalValue, msg.value);
		}
		if (msg.value > totalValue) {
			_transfer(msg.sender, msg.value - totalValue);
		}
		_transfer(owner(), totalValue);
		_mint(to, TOKENID, amount, "");
	}

	function _transfer(address to, uint256 value) internal {
		(bool success, ) = to.call{ value: value }("");
		require(success, "refund failed");
	}

	function setTokenURI(string memory _uri) external onlyOwner {
		tokenURI = _uri;
		emit URI(tokenURI, TOKENID);
	}

	function uri(uint256 tokenId) public view override returns (string memory) {
		return tokenURI;
	}

	function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal override(ERC1155SupplyUpgradeable, ERC1155Upgradeable) {
		ERC1155SupplyUpgradeable._update(from, to, ids, values);
	}
}
