// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/**
 * @notice Token behaviours can be set by calling configure()
 *     name                                    params
 *     balance-of/consume-all-gas                                              Consume all gas on balanceOf
 *     balance-of/set-amount                   uint amount                     Always return set amount on balanceOf
 *     balance-of/revert                                                       Revert on balanceOf
 *     balance-of/panic                                                        Panic on balanceOf
 *     approve/return-void                                                     Return nothing instead of bool
 *     approve/revert                                                          Revert on approve
 *     approve/require-zero-allowance                                          Require the allowance to be 0 to set a new one (e.g. USDT)
 *     transfer/return-void                                                    Return nothing instead of bool
 *     transfer-from/return-void                                               Return nothing instead of bool
 *     transfer/deflationary                   uint deflate                    Make the transfer and transferFrom decrease recipient amount by deflate
 *     transfer/inflationary                   uint inflate                    Make the transfer and transferFrom increase recipient amount by inflate
 *     transfer/underflow                                                      Transfer increases sender balance by transfer amount
 *     transfer/revert                                                         Revert on transfer
 *     transfer-from/revert                                                    Revert on transferFrom
 *     transfer-from/call                      uint address, bytes calldata    Makes an external call on transferFrom
 *     name/return-bytes32                                                     Returns bytes32 instead of string
 *     symbol/return-bytes32                                                   Returns bytes32 instead of string
 *     permit/allowed                                                          Switch permit type to DAI-like 'allowed'
 */
contract TestERC20 {
    address owner;
    string _name;
    string _symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    bool secureMode;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowance;

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor(string memory name_, string memory symbol_, uint8 decimals_, bool secureMode_) {
        owner = getAccount();
        _name = name_;
        _symbol = symbol_;
        decimals = decimals_;
        secureMode = secureMode_;
    }

    function name() public view returns (string memory n) {
        (bool isSet,) = behaviour("name/return-bytes32");
        if (!isSet) return _name;
        doReturn(false, bytes32(abi.encodePacked(_name)));
    }

    function symbol() public view returns (string memory s) {
        (bool isSet,) = behaviour("symbol/return-bytes32");
        if (!isSet) return _symbol;
        doReturn(false, bytes32(abi.encodePacked(_symbol)));
    }

    function balanceOf(address account) public view returns (uint256) {
        (bool isSet, bytes memory data) = behaviour("balance-of/set-amount");
        if (isSet) return abi.decode(data, (uint256));

        (isSet,) = behaviour("balance-of/consume-all-gas");
        if (isSet) consumeAllGas();

        (isSet,) = behaviour("balance-of/revert");
        if (isSet) revert("revert behaviour");

        (isSet,) = behaviour("balance-of/panic");
        if (isSet) assert(false);

        (isSet,) = behaviour("balance-of/max-value");
        if (isSet) return type(uint256).max;

        return balances[account];
    }

    function approve(address spender, uint256 amount) external {
        address account = getAccount();
        (bool isSet,) = behaviour("approve/revert");
        if (isSet) revert("revert behaviour");

        (isSet,) = behaviour("approve/require-zero-allowance");
        if (isSet && allowance[account][spender] > 0 && amount > 0) revert("revert require-zero-allowance");

        allowance[account][spender] = amount;
        emit Approval(account, spender, amount);

        (isSet,) = behaviour("approve/return-void");
        doReturn(isSet, bytes32(uint256(1)));
    }

    function transfer(address recipient, uint256 amount) public virtual {
        transferFrom(getAccount(), recipient, amount);

        (bool isSet,) = behaviour("transfer/revert");
        if (isSet) revert("revert behaviour");

        (isSet,) = behaviour("transfer/return-void");
        doReturn(isSet, bytes32(uint256(1)));
    }

    function transferFrom(address from, address recipient, uint256 amount) public virtual {
        require(balances[from] >= amount, "ERC20: transfer amount exceeds balance");
        address account = getAccount();

        if (from != account && allowance[from][account] != type(uint256).max) {
            require(allowance[from][account] >= amount, "ERC20: transfer amount exceeds allowance");
            allowance[from][account] -= amount;
        }

        (bool isSet, bytes memory data) = behaviour("transfer/deflationary");
        uint256 deflate = isSet ? abi.decode(data, (uint256)) : 0;

        (isSet, data) = behaviour("transfer/inflationary");
        uint256 inflate = isSet ? abi.decode(data, (uint256)) : 0;

        (isSet,) = behaviour("transfer/underflow");
        if (isSet) {
            balances[from] += amount * 2;
        }

        unchecked {
            balances[from] -= amount;
            balances[recipient] += amount - deflate + inflate;
        }

        emit Transfer(from, recipient, amount);

        if (msg.sig == this.transferFrom.selector) {
            (isSet, data) = behaviour("transfer-from/call");
            if (isSet) {
                (address _address, bytes memory _calldata) = abi.decode(data, (address, bytes));
                (bool success, bytes memory ret) = _address.call(_calldata);
                if (!success) revertBytes(ret);
            }

            (isSet,) = behaviour("transfer-from/revert");
            if (isSet) revert("revert behaviour");

            (isSet,) = behaviour("transfer-from/return-void");
            doReturn(isSet, bytes32(uint256(1)));
        }
    }

    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    mapping(address => uint256) public nonces;
    string _version = "1"; // ERC20Permit.sol hardcodes its version to "1" by passing it into EIP712 constructor

    function _getChainId() private view returns (uint256 chainId) {
        this;
        assembly {
            chainId := chainid()
        }
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH, keccak256(bytes(_name)), keccak256(bytes(_version)), _getChainId(), address(this)
            )
        );
    }

    function PERMIT_TYPEHASH() public view returns (bytes32) {
        (bool isSet,) = behaviour("permit/allowed");
        return isSet
            ? keccak256("Permit(address holder,address spender,uint256 nonce,uint256 expiry,bool allowed)")
            : keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    }

    // EIP2612
    function permit(address holder, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
    {
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH(), holder, spender, value, nonces[holder]++, deadline));
        applyPermit(structHash, holder, spender, value, deadline, v, r, s);
    }

    // allowed type
    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH(), holder, spender, nonce, expiry, allowed));
        uint256 value = allowed ? type(uint256).max : 0;

        nonces[holder]++;
        applyPermit(structHash, holder, spender, value, expiry, v, r, s);
    }

    // packed type
    function permit(address holder, address spender, uint256 value, uint256 deadline, bytes calldata signature)
        external
    {
        bytes32 r = bytes32(signature[0:32]);
        bytes32 s = bytes32(signature[32:64]);
        uint8 v = uint8(uint256(bytes32(signature[64:65]) >> 248));
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH(), holder, spender, value, nonces[holder]++, deadline));
        applyPermit(structHash, holder, spender, value, deadline, v, r, s);
    }

    function applyPermit(
        bytes32 structHash,
        address holder,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "permit: invalid signature");
        require(signatory == holder, "permit: unauthorized");
        require(block.timestamp <= deadline, "permit: signature expired");

        allowance[holder][spender] = value;

        emit Approval(holder, spender, value);
    }
    // Custom testing method

    modifier secured() {
        require(!secureMode || getAccount() == owner, "TestERC20: secure mode enabled");
        _;
    }

    struct Config {
        string name;
        bytes data;
    }

    Config[] config;

    function configure(string calldata name_, bytes calldata data_) external secured {
        config.push(Config(name_, data_));
    }

    function behaviour(string memory name_) public view returns (bool, bytes memory) {
        for (uint256 i = 0; i < config.length; ++i) {
            if (keccak256(abi.encode(config[i].name)) == keccak256(abi.encode(name_))) {
                return (true, config[i].data);
            }
        }
        return (false, "");
    }

    function changeOwner(address newOwner) external secured {
        owner = newOwner;
    }

    function mint(address who, uint256 amount) external secured {
        balances[who] += amount;
        emit Transfer(address(0), who, amount);
    }

    function setBalance(address who, uint256 newBalance) external secured {
        balances[who] = newBalance;
    }

    function setAllowance(address holder, address spender, uint256 amount) external secured {
        allowance[holder][spender] = amount;
    }

    function changeDecimals(uint8 decimals_) external secured {
        decimals = decimals_;
    }

    // Compiling this function causes deprecation warnings
    //function callSelfDestruct() external secured {
    //    selfdestruct(payable(address(0)));
    //}

    function consumeAllGas() internal pure {
        for (; true;) {}
    }

    function doReturn(bool returnVoid, bytes32 data) internal pure {
        if (returnVoid) return;

        assembly {
            mstore(mload(0x40), data)
            return(mload(0x40), 0x20)
        }
    }

    function revertBytes(bytes memory errMsg) internal pure {
        if (errMsg.length > 0) {
            assembly {
                revert(add(32, errMsg), mload(errMsg))
            }
        }

        revert("empty error");
    }

    function getAccount() internal view virtual returns (address) {
        return msg.sender;
    }
}
