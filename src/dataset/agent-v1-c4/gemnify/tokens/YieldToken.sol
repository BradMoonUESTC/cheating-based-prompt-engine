// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IYieldTracker} from "./interfaces/IYieldTracker.sol";
import {IYieldToken} from "./interfaces/IYieldToken.sol";

contract YieldToken is IERC20, IYieldToken {
    using Math for uint256;
    using SafeERC20 for IERC20;

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public override totalSupply;
    uint256 public nonStakingSupply;

    address public owner;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

    address[] public yieldTrackers;
    mapping(address => bool) public nonStakingAccounts;
    mapping(address => bool) public admins;

    bool public inWhitelistMode;
    mapping(address => bool) public whitelistedHandlers;

    modifier onlyOwner() {
        require(msg.sender == owner, "YieldToken: forbidden");
        _;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender], "YieldToken: forbidden");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) {
        name = _name;
        symbol = _symbol;
        owner = msg.sender;
        admins[msg.sender] = true;
        _mint(msg.sender, _initialSupply);
    }

    function setInfo(
        string memory _name,
        string memory _symbol
    ) external onlyOwner {
        name = _name;
        symbol = _symbol;
    }

    function setYieldTrackers(
        address[] memory _yieldTrackers
    ) external onlyOwner {
        yieldTrackers = _yieldTrackers;
    }

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    function addAdmin(address _account) external onlyOwner {
        admins[_account] = true;
    }

    function removeAdmin(address _account) external override onlyOwner {
        admins[_account] = false;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyOwner {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function setInWhitelistMode(bool _inWhitelistMode) external onlyOwner {
        inWhitelistMode = _inWhitelistMode;
    }

    function setWhitelistedHandler(
        address _handler,
        bool _isWhitelisted
    ) external onlyOwner {
        whitelistedHandlers[_handler] = _isWhitelisted;
    }

    function addNonStakingAccount(address _account) external onlyAdmin {
        require(
            !nonStakingAccounts[_account],
            "YieldToken: _account already marked"
        );
        _updateRewards(_account);
        nonStakingAccounts[_account] = true;
        nonStakingSupply = nonStakingSupply + balances[_account];
    }

    function removeNonStakingAccount(address _account) external onlyAdmin {
        require(
            nonStakingAccounts[_account],
            "YieldToken: _account not marked"
        );
        _updateRewards(_account);
        nonStakingAccounts[_account] = false;
        nonStakingSupply = nonStakingSupply - balances[_account];
    }

    function recoverClaim(
        address _account,
        address _receiver
    ) external onlyAdmin {
        for (uint256 i = 0; i < yieldTrackers.length; i++) {
            address yieldTracker = yieldTrackers[i];
            IYieldTracker(yieldTracker).claim(_account, _receiver);
        }
    }

    function claim(address _receiver) external {
        for (uint256 i = 0; i < yieldTrackers.length; i++) {
            address yieldTracker = yieldTrackers[i];
            IYieldTracker(yieldTracker).claim(msg.sender, _receiver);
        }
    }

    function totalStaked() external view override returns (uint256) {
        return totalSupply - nonStakingSupply;
    }

    function balanceOf(
        address _account
    ) external view override returns (uint256) {
        return balances[_account];
    }

    function stakedBalance(
        address _account
    ) external view override returns (uint256) {
        if (nonStakingAccounts[_account]) {
            return 0;
        }
        return balances[_account];
    }

    function transfer(
        address _recipient,
        uint256 _amount
    ) external override returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function allowance(
        address _owner,
        address _spender
    ) external view override returns (uint256) {
        return allowances[_owner][_spender];
    }

    function approve(
        address _spender,
        uint256 _amount
    ) external override returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external override returns (bool) {
        require(
            allowances[_sender][msg.sender] >= _amount,
            "YieldToken: transfer amount exceeds allowance"
        );
        uint256 nextAllowance = allowances[_sender][msg.sender] - _amount;
        _approve(_sender, msg.sender, nextAllowance);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function _mint(address _account, uint256 _amount) internal {
        require(_account != address(0), "YieldToken: mint to the zero address");

        _updateRewards(_account);

        totalSupply = totalSupply + (_amount);
        balances[_account] = balances[_account] + (_amount);

        if (nonStakingAccounts[_account]) {
            nonStakingSupply = nonStakingSupply + (_amount);
        }

        emit Transfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) internal {
        require(
            _account != address(0),
            "YieldToken: burn from the zero address"
        );

        _updateRewards(_account);

        require(
            balances[_account] >= _amount,
            "YieldToken: burn amount exceeds balance"
        );

        balances[_account] = balances[_account] - _amount;
        totalSupply = totalSupply - (_amount);

        if (nonStakingAccounts[_account]) {
            nonStakingSupply = nonStakingSupply - (_amount);
        }

        emit Transfer(_account, address(0), _amount);
    }

    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) private {
        require(
            _sender != address(0),
            "YieldToken: transfer from the zero address"
        );
        require(
            _recipient != address(0),
            "YieldToken: transfer to the zero address"
        );

        if (inWhitelistMode) {
            require(
                whitelistedHandlers[msg.sender],
                "YieldToken: msg.sender not whitelisted"
            );
        }

        _updateRewards(_sender);
        _updateRewards(_recipient);

        require(
            balances[_sender] >= _amount,
            "YieldToken: transfer amount exceeds balance"
        );

        balances[_sender] = balances[_sender] - _amount;
        balances[_recipient] = balances[_recipient] + (_amount);

        if (nonStakingAccounts[_sender]) {
            nonStakingSupply = nonStakingSupply - (_amount);
        }
        if (nonStakingAccounts[_recipient]) {
            nonStakingSupply = nonStakingSupply + (_amount);
        }

        emit Transfer(_sender, _recipient, _amount);
    }

    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) private {
        require(
            _owner != address(0),
            "YieldToken: approve from the zero address"
        );
        require(
            _spender != address(0),
            "YieldToken: approve to the zero address"
        );

        allowances[_owner][_spender] = _amount;

        emit Approval(_owner, _spender, _amount);
    }

    function _updateRewards(address _account) private {
        for (uint256 i = 0; i < yieldTrackers.length; i++) {
            address yieldTracker = yieldTrackers[i];
            IYieldTracker(yieldTracker).updateRewards(_account);
        }
    }
}
