// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IMemeToken.sol";
import "./interfaces/IMemePool.sol";
import "./interfaces/ITokenFactory.sol";
import "./interfaces/IPoolFactory.sol";
import "./TokenFactory.sol";
import "./PoolFactory.sol";

contract Platform is Ownable {

    struct TokenInfo {
        address dev;
        uint64 unlockTime;
        uint8 poolType;
        address poolAddress;
        address tokenAddress;
        uint256 lockAmount;
    }

    /// @dev Platform Version
    uint256 constant public VERSION = 1;
    /// @dev Min Lock LP Time TODO Pre-deployment decision
    uint96 constant public MIN_LOCKTIME = 7 days;
    /// @dev Min Native Dev Add to The Pool TODO Pre-deployment decision
    uint256 constant public MIN_NATIVE = 1E18;
    /// @dev DEPLOY FEE In This Contract TODO Pre-deployment decision
    uint256 constant public DEPLOY_FEE = 1E17;
    address immutable public BASIC_MODULE;

    uint8 public poolVersion;
    mapping(uint8 => address) public poolFactories;
    IPoolFactory public poolFactory;
    mapping(string => TokenInfo) public tokenInfos;
    mapping(address => bool) public registeredModules;


    //////////////////////////////// Errors ////////////////////////////////

    error Locked();
    error NativeAmount();
    error LockTimeTooShort();
    error Registered();
    error InvalidModule();


    //////////////////////////////// Init ////////////////////////////////

    constructor(address _basicModule) Ownable(msg.sender) {
        BASIC_MODULE = _basicModule;
    }


    //////////////////////////////// Events ////////////////////////////////

    // OWNER EVENT
    event SetPoolFactory(uint8 version, address poolFactory);
    event CollectFee(address to, uint256 amount);
    event ManageModule(address module, bool isAdd);
    // DEV EVENT
    event Deploy(string symbol, address tokenAddress, uint8 poolVersion, address poolAddress, address module, uint96 unlockTime, uint256 native);
    event UnlockLP(string symbol, address dev, uint256 amount);


    //////////////////////////////// Owner Functions ////////////////////////////////

    /// @notice Register Official Module
    /// @param module, Module Address
    /// @param isAdd, Add or Delete
    function registerModule(address module, bool isAdd) onlyOwner external {
        registeredModules[module] = isAdd;
        emit ManageModule(module, isAdd);
    }

    /// @notice Set New Pool Factory
    /// @param _poolFactory, new Pool Factory
    function setupPoolFactory(address _poolFactory) onlyOwner external {
        uint8 _version = ++poolVersion;
        poolFactories[_version] = _poolFactory;
        poolFactory = IPoolFactory(_poolFactory);
        emit SetPoolFactory(_version, _poolFactory);
    }

    /// @notice Collect Protocol Fee
    /// @param _to, Send Fee To
    /// @param _amount, Collect Amount
    function collectFee(address _to, uint256 _amount) onlyOwner external {
        uint256 totalFee = address(this).balance;
        if (_amount > totalFee) { _amount = totalFee; }
        payable(_to).transfer(_amount);
        emit CollectFee(_to, _amount);
    }


    //////////////////////////////// Dev Functions ////////////////////////////////

    /// @notice Deploy Meme Pool By Devs
    /// @param symbol, Token Symbol
    /// @param lockTime, Lock Lp Time
    /// @param module, Token Module
    function deployMemePool(
        string calldata symbol,
        uint64 lockTime,
        uint256 feeParam,
        address module
    ) external payable {
        address dev = msg.sender;
        // if (reserveRate > MAX_RESERVE_RATE) { revert ReserveTooMuch(); }
        if (lockTime < MIN_LOCKTIME) { revert LockTimeTooShort(); }
        TokenInfo storage info = tokenInfos[symbol];
        if (info.tokenAddress != address(0)) { revert Registered(); }
        module = _checkModule(module);
        uint256 native = msg.value - DEPLOY_FEE;
        if (native < MIN_NATIVE) { revert NativeAmount(); }
        // Deploy Pool
        (address poolAddress, address tokenAddress) = poolFactory.deploy(symbol, feeParam, module);
        uint8 _version = poolVersion;
        // Mint Token To Pool
        IMemeToken(tokenAddress).initialize(poolAddress);
        // Lock Lp
        uint256 lockAmount = IMemePool(poolAddress).initialize{value: native}();
        uint64 unlockTime = uint64(block.timestamp) + lockTime;
        // Save
        info.dev = dev;
        info.unlockTime = unlockTime;
        info.poolType = _version;
        info.tokenAddress = tokenAddress;
        info.poolAddress = poolAddress;
        info.lockAmount = lockAmount;
        emit Deploy(symbol, tokenAddress, _version, poolAddress, module, unlockTime, native);
    }

    /// @notice Unlock LP Token
    /// @param symbol, Token Symbol
    function unlock(string calldata symbol) external {
        TokenInfo storage info = tokenInfos[symbol];
        address dev = info.dev;
        uint256 lockAmount = info.lockAmount;
        if (block.timestamp < info.unlockTime) { revert Locked(); }
        IERC20(info.tokenAddress).transfer(dev, lockAmount);
        info.lockAmount = 0;
        emit UnlockLP(symbol, dev, lockAmount);
    }

    function _checkModule(address _moudule) internal view returns (address) {
        if (_moudule == address(0)) {
            return BASIC_MODULE;
        } else {
            if (registeredModules[_moudule]) {
                return _moudule;
            } else {
                revert InvalidModule();
            }
        }
    }

    receive() external payable {}

}
