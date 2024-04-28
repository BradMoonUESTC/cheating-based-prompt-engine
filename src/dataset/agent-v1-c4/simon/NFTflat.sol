// SPDX-License-Identifier: GPL-3.0
pragma solidity <0.9.0 >=0.7.0;

// src/IERC.sol

/// import "hardhat/console.sol";

interface IERC20_ {
    /////////////////////////////////////////////////////// interface of the ERC20 standard as defined in the EIP
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    ///////////////////////////////////////////////////////
}
interface IERC20 is IERC20_ {
    ///////////////////////////////////////////////////////
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
interface IERC20Receiver {
    ///////////////////////////////////////////////////////
    function onERC20Received(address from, address to, uint256 amount, uint256 data) external returns(bool);
}

interface IERC721Receiver {
    ///////////////////////////////////////////////////////
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}
interface IERC165 {
    ///////////////////////////////////////////////////////
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
interface IERC721Enumerable_ {
    ///////////////////////////////////////////////////////
/// function totalSupply() external view returns(uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns(uint256);
    function tokenByIndex(uint256 index) external view returns(uint256);
}
interface IERC721Metadata_ {
    ///////////////////////////////////////////////////////
/// function name() external view returns(string memory);
/// function symbol() external view returns(string memory);
    function tokenURI(uint256 tokenId) external view returns(string memory);
}
interface IERC721_ {
    ///////////////////////////////////////////////////////
/// function balanceOf(address owner) external view returns(uint256 balance);
    function ownerOf(uint256 tokenId) external view returns(address);
    function getApproved(uint256 tokenId) external view returns(address);
    function isApprovedForAll(address owner, address operator) external view returns(bool);
    ///////////////////////////////////////////////////////
/// function transferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
/// function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    ///////////////////////////////////////////////////////
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
}
interface IESC20 {
    ///////////////////////////////////////////////////////
    function Insight(address caller, address from, address to) external view returns(uint256,uint160);
    function Escape(address caller, address from, address to, uint256 amount) external returns(bool);
}

interface ISwap {
    ///////////////////////////////////////////////////////
    function Swap(
        address payer,                                  /// shall =caller if 'token' != USSSD
                                                        /// or, caller must own a debt of payer and owe to this contract
        uint256 amount,                                 /// amount of 'token' to sell
        address token,                                  /// IERC20 token to sell
        address tokenToReceive,                         /// IERC20 token to receive
        uint256 minToReceive,                           /// minimum amount of 'tokenToReceive' to swap
        address recipient                               /// target wallet
    ) external returns(uint256);                        /// actual tokens received
    ///////////////////////////////////////////////////////
    function Estimate(uint256 amount, address token, address tokenToReceive) external view returns(uint256);
}

///////////////////////////////////////////////////////////
interface IDaoAgency {
    function ApplyDao(address agent) external returns (address);
}

library Num {
    ///////////////////////////////////////////////////////
    uint256 public constant MAX256      = type(uint256).max;
    uint256 public constant MAX160      = type(uint160).max;
    uint128 public constant MAX128      = type(uint128).max;
    uint64  public constant MAX64       = type(uint64 ).max;
    uint32  public constant MAX32       = type(uint32 ).max;
    uint256 public constant GWEI        = 10**9;
    uint256 public constant TWEI        = 10**12;
    uint256 public constant _0_000001   = 10**12;
    uint256 public constant _0_00001    = 10**13;
    uint256 public constant _0_0001     = 10**14;
    uint256 public constant _0_001      = 10**15;
    uint256 public constant _0_01       = 10**16;
    uint256 public constant _0_1        = 10**17;
    uint256 public constant _1          = 10**18;
    uint256 public constant _10         = 10**19;
    uint256 public constant _100        = 10**20;
    uint256 public constant _1000       = 10**21;
    uint256 public constant _10000      = 10**22;
    uint256 public constant _100000     = 10**23;
    uint256 public constant _1000000    = 10**24;
    ///////////////////////////////////////////////////////
    uint256 public constant CENT        = 10**16;
    uint256 public constant DIME        = 10**17;
    ///////////////////////////////////////////////////////
    address public constant _0          = address(0);
    address public constant MAP_        = address(0x10);
    address public constant _MAP        = address(0xFFFFFFFFFF);
    address public constant ESC         = address(0xFFFFFFFFFFFFFFFF);
    address public constant NULL        = address(type(uint160).max);
    ///////////////////////////////////////////////////////
    function _Mapped(address a) internal pure returns(bool) {
        return (MAP_ <= a)&&(a <= _MAP);
    }
    function _Mapped(address a, address b) internal pure returns(bool) {
        return _Mapped((a != NULL) ? a : b);
    }
    function _Escaped(address a) internal pure returns(bool) {
        return (MAP_ <= a)&&(a <= ESC);
    }
    function _Escaped(address a, address b) internal pure returns(bool) {
        return _Escaped((a != NULL) ? a : b);
    }
    ///////////////////////////////////////////////////////
    uint160 public constant _900        =  0x900;
    uint160 public constant URL         =  0x192;
    uint160 public constant GAS         =  0x9a5;
    ///////////////////////////////////////////////////////
    uint160 public constant SN          =   0x50;
    uint160 public constant VERSION     =   0x51;
    uint160 public constant VER2        =   0x52;
    uint160 public constant ACCOUNT     =   0xAC;
    uint160 public constant BLK         =   0xB1;
    uint160 public constant HASH        =   0xB5;
    uint160 public constant BALANCE     =   0xBA;
    uint160 public constant ESCAPE      =   0xE5;
    uint160 public constant ESCAPED     =   0xED;
    uint160 public constant CTX         =   0xFC;
    uint160 public constant STATUS      =   0xFF;
    ///////////////////////////////////////////////////////
    uint160 public constant USD         = 0xadd0;
    uint160 public constant USD1        = 0xadd1;
    uint160 public constant USD2        = 0xadd2;
    uint160 public constant TOKEN       = 0xadd8;
    uint160 public constant USD_        = 0xadd9;
    uint160 public constant NFT         = 0xaddA;
    uint160 public constant BIND        = 0xaddB;
    uint160 public constant SWAP        = 0xaddC;
    uint160 public constant DAO         = 0xaddD;
    uint160 public constant OWNER       = 0xaddE;
    uint160 public constant DELEGATE    = 0xaddF;
    ///////////////////////////////////////////////////////
    uint160 public constant DEBT        = 0xDeb0;
    uint160 public constant DEBTOFF     = 0xDeb1;
    uint160 public constant DEBTPASS    = 0xDeb2;
    ///////////////////////////////////////////////////////
}

// src/ERC.sol

abstract contract ERC is IERC20_ {
    string  internal  _symbol;
    uint8   internal  _decimals;
    uint256 internal  _url;
    uint256 internal  _ver;                             /// version
    address internal  _owner;                           /// superuser
    address internal  _minter;                          /// optional minter contract
    ///////////////////////////////////////////////////////
    struct Permit {
        uint128 allowance;
        uint128 limit;
    }
    uint256 internal  _totalSupply;
    mapping(address => mapping(address => Permit))  internal _permits;
    ///////////////////////////////////////////////////////
    constructor(
        string memory symbol_,
        uint8 decimals_,
        uint256 max,                                    /// maximum tokens to mint, 0 as unlimited
        uint160 owner,
        uint256 version
    ) {
        unchecked {
            address me = address(this);
            uint128 mintable = (max == 0) ? Num.MAX128 : uint128(max);
            _permits[me][_owner = address(owner)].limit =
            _permits[Num._0][me].limit = mintable;      /// mintability
            _ver = version;
            _symbol = symbol_;
            _decimals = decimals_;
        }
    }
    ///////////////////////////////////////////////////////
    modifier ByMint() {
        require(msg.sender == _minter,"()");
        _;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function name() external view virtual override returns(string memory) {
        uint256 url = _url;
        return (url == 0) ? _symbol : _toString(url);
    }
    ///////////////////////////////////////////////////////
    function symbol() public view virtual override returns(string memory) {
        return _symbol;
    }
    ///////////////////////////////////////////////////////
    function decimals() external view virtual override returns(uint8) {
        return _decimals;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function _permitted(address permitter, address permittee, uint256 amount) internal virtual returns(bool) {
        uint128 n = uint128(amount);
        unchecked {
            if((permitter == Num._0)                    /// this is exclusively for permission to config this contract
             &&(permittee == _owner))                   /// and for contract owner only! (unconfiguratable after giving up ownership)
                return true;
            Permit memory permit = _permits[permitter][permittee];
            if(permit.limit >= Num.MAX128)              /// permission between users enable futher uses of defi/game-fi
                return true;
            if(permit.limit < n)
                return false;
            permit.limit -= n;
            _permits[permitter][permittee] = permit;
            return true;
        }
    }
    /////////////////////////////////////////////////////// permission can be issued exclusively by the permitter itself
    function _issuePermit(address permitter, address permittee, uint256 amount) internal virtual returns(bool) {
        uint256 n = uint128(amount);
        unchecked {
            if((n == 0)||(permittee == permitter))
                return false;
            Permit memory p = _permits[permitter][permittee];
            if(p.limit < Num.MAX128) {
                n += p.limit;                           /// be careful to avoid overflow
                p.limit = (n < Num.MAX128) ? uint128(n) : Num.MAX128;
                _permits[permitter][permittee] = p;
            }
            return true;
        }
    }
    /////////////////////////////////////////////////////// permission can be cancelled only by its holder!
    function _cancelPermit(address permitter, address permittee, address payer, uint256 amount) internal virtual returns(bool) {
        uint128 n = uint128(amount);
        unchecked {
            if(permittee == permitter)
                return false;
            Permit memory p = _permits[permitter][permittee];
            if(p.limit == 0)
                return false;
            if((n == 0)||(n >= p.limit))                /// cancel all of remaining permits
                n = p.limit;
            bool toAllowance = (payer == permitter);
            if(toAllowance) {
                amount = uint256(n)+p.allowance;        /// convert permission into allowance
                p.allowance = (amount < Num.MAX128) ? uint128(amount) : Num.MAX128;
            }
            else {
                Permit memory pay = _permits[payer][permitter];
                if(pay.limit == 0)
                    return false;
                if(n > pay.limit) n = pay.limit;        /// cannot pass permits over payer's limit
                if(pay.limit < Num.MAX128) {
                    pay.limit -= n;                     /// (payer->permitter) permission reduced
                    _permits[payer][permitter] = pay;
                }
                if(payer != permittee) {
                    pay = _permits[payer][permittee];
                    amount = uint256(n)+pay.limit;      /// pass permission to payer, or eliminate debt loop
                    pay.limit = (amount < Num.MAX128) ? uint128(amount) : Num.MAX128;
                    _permits[payer][permittee] = pay;
                }
            }
            if(p.limit < Num.MAX128) p.limit -= n;      /// permission (permitter->permittee) cancelled
            else if(!toAllowance)
                return true;
            _permits[permitter][permittee] = p;
            return true;
        }
    }
    /////////////////////////////////////////////////////// permission check (for owner) to config this contract
    function _config(uint256 permission, uint256 value) internal virtual returns(bool) {
        require(_permitted(Num._0,msg.sender,permission),"!");
        return value >= 0;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function _toString(uint256 u) internal view virtual returns(string memory) {
        unchecked {
            uint b;
            for(; b < 256; b += 8)
                if((0xFF&(u>>b)) == 0)
                    break;
            if(b == 0) return "";
            bytes memory z = new bytes(b>>3);
            for(uint i = 0; i < b; i += 8)
                z[i>>3] = bytes1(uint8(u>>i));
            u = _url;
            return string(z);
        }
    }
}

// src/NFTIndex.sol

contract NFTIndex {
    uint256 internal  _ver;                             /// version
    address internal  _nft;
    ///////////////////////////////////////////////////////
    struct Owner {
        address a;
        uint64  idx;
    }
    struct Operator {
        address a;
        uint64  idx;
    }
    uint64  internal _n;
    uint64  internal _maxId;
    mapping(uint64  => uint64)                          internal _totalIds;
    mapping(uint224 => uint64)                          internal _ownedIds;
    mapping(uint64  => Owner)                           internal _owners;
    mapping(uint64  => Operator)                        internal _operators;
    mapping(address => uint64)                          internal _balances;
    mapping(uint96  => uint256)                         internal _meta;
    ///////////////////////////////////////////////////////
    constructor(
        address nft,
        uint256 version
    ) {
        unchecked {
            _nft = nft;
            _ver = version;
        }
    }
    ///////////////////////////////////////////////////////
    modifier ByNft() {
        require(msg.sender == _nft,"()");
        _;
    }
    ///////////////////////////////////////////////////////
    function Nft() external view virtual returns(address) {
        return _nft;
    }
    ///////////////////////////////////////////////////////
    function Version() external view virtual returns(uint256) {
        return _ver;
    }
    ///////////////////////////////////////////////////////
    function Minted() external view virtual returns(uint256) {
        return _maxId;
    }
    ///////////////////////////////////////////////////////
    function Meta(uint256 tokenId, uint256 i) external view virtual returns(uint256) {
        return _meta[uint64(tokenId)|uint96(i<<64)];
    }
    ///////////////////////////////////////////////////////
    function SetMeta(address operator, uint256 tokenId, uint256 i, uint256 v) ByNft external virtual returns(bool) {
        uint64 id = uint64(tokenId);
        unchecked {
            require((id <= _maxId)&&
                    ((i <= 0xFF)
                    ||(operator == _owners[id].a)
                    ||(operator == _operators[id].a)),"*");
            _meta[id|uint96(i<<64)] = v;
            return true;
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function totalSupply() external view virtual returns(uint256) {
        return _n;
    }
    ///////////////////////////////////////////////////////
    function balanceOf(address account) external view returns(uint256) {
        return _balances[account];
    }
    ///////////////////////////////////////////////////////
    function tokenOfOwnerByIndex(address owner, uint256 index) external view virtual returns(uint256) {
        uint224 idx = uint64(index);
        unchecked {
            idx <<= 160;
            return _ownedIds[idx|uint160(owner)];
        }
    }
    ///////////////////////////////////////////////////////
    function tokenByIndex(uint256 index) external view virtual returns(uint256) {
        return _totalIds[uint64(index)];
    }
    ///////////////////////////////////////////////////////
    function tokenURI(uint256 tokenId, uint256 url) external view virtual returns(string memory) {
        unchecked {
            tokenId = toDecimal(tokenId);
            return catToString(url,tokenId);
        }
    }
    ///////////////////////////////////////////////////////
    function ownerOf(uint256 tokenId) external view virtual returns(Owner memory) {
        return _owners[uint64(tokenId)];
    }
    ///////////////////////////////////////////////////////
    function operatorOf(uint256 tokenId) external view virtual returns(Operator memory) {
        return _operators[uint64(tokenId)];
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function approve(address to, uint256 tokenId) ByNft external virtual returns(address) {
        uint64 id = uint64(tokenId);
        unchecked {
            _operators[id].a = to;
            return _owners[id].a;
        }
    }
    ///////////////////////////////////////////////////////
    function safeTransferFrom(address operator, address from, address to, uint256 tokenId, bytes calldata data, bool approved)
                ByNft external virtual returns(bool) {
        unchecked {
            require(tokenId <= _maxId,"#");
            if(_transfer(operator,from,to,uint64(tokenId),approved))
                return false;
            if(to.code.length == 0)
                return true;
            try IERC721Receiver(to).onERC721Received(operator,from,tokenId,data) returns(bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                require(reason.length < 0,"=");
                return false;
            }
        }
    }
    ///////////////////////////////////////////////////////
    function burn(address operator, uint256 tokenId, bool approved) ByNft external virtual returns(bool) {
        uint64 id = uint64(tokenId);
        unchecked {
            require((id <= _maxId)&&
                _transfer(operator,Num._0,Num._0,id,approved),"#");
            return true;
        }
    }
    ///////////////////////////////////////////////////////
    function mint(address to, uint256 amount) ByNft external virtual returns(uint256) {
        uint64 n = uint64(amount);
        unchecked {
            uint64 id = _maxId;
            uint64 i = Num.MAX64-id;
            if(n > i) n = i;
            if(n == 0)
                return 0;
            _maxId = id+n;
            Owner memory owner;
            Operator memory op;
            owner.idx = _balances[Num._0];
            _balances[Num._0] = owner.idx+n;
            for(i = 0; i < n; i ++) {
                op.idx = id ++;
                uint224 idx = owner.idx ++;
                idx <<= 160;
                _operators[id] = op;
                _owners[id] = owner;
                _ownedIds[idx] = id;
                _totalIds[op.idx] = id;
                uint b = id&0xFF;
                uint256 hash = uint256(blockhash(block.number-1));
                _meta[id|(0x1<<64)] = (hash<<b)|(hash>>(256-b));
            }
            if(to != Num._0) {
                id = _maxId;
                for(i = 0; i < n; i ++)
                    _transfer(Num._0,Num._0,to,id --,true);
            }
            return n;
        }
    }
    ///////////////////////////////////////////////////////
    function transfer(address operator, address from, address to, uint256 tokenId, bool approved) ByNft external virtual returns(bool) {
        require(tokenId <= _maxId,"#");
        return _transfer(operator,from,to,uint64(tokenId),approved);
    }
    ///////////////////////////////////////////////////////
    function _transfer(address operator, address from, address to, uint64 id, bool approved) internal virtual returns(bool) {
        unchecked {
            Owner memory owner = _owners[id];
            if(to == owner.a)
                return false;
            Operator memory op = _operators[id];
            if(from == Num._0) from = owner.a;
            require((from == owner.a)&&
                    (approved
                    ||(operator == op.a)
                    ||(operator == owner.a))
                    &&_transferCheck(owner.a,to,id),
                        "!");
            uint224 idx = owner.idx;
            idx <<= 160;
            idx |= uint160(from);
            uint64 last = uint64(-- _balances[from]);
            if(owner.idx >= last)                       /// last in owner's list
                _ownedIds[idx] = 0;
            else {
                uint224 toe = last;
                toe <<= 160;
                toe |= uint160(from);
                _owners[_ownedIds[idx] = _ownedIds[toe]].idx = owner.idx;
                _ownedIds[toe] = 0;                     /// swap trailing nft to where to be transferred out
            }
            idx = owner.idx = _balances[owner.a = to] ++;
            idx <<= 160;                                /// one more for recipient
            idx |= uint160(to);
            _ownedIds[idx] = id;                        /// push transferred nft to the end of recipient's list
            _owners[id] = owner;                        /// nft transferred
            last = uint64(_n);                          /// next to the end of valid list
            bool swap;
            if(from == Num._0) {                        /// mint a new one
                swap = (op.idx > last);                 /// swap to the trailing slot
                _n = last+1;
            }
            else if(to == Num._0) {                     /// burn this one
                swap = (op.idx < -- last);              /// swap to the next slot after valid list
                _n = last;
            }
            bool modified = (op.a != Num._0);
            op.a = Num._0;                              /// clear operator after transfer
            if(swap) {
                _totalIds[op.idx] = _totalIds[last];
                _totalIds[op.idx = last] = id;
                modified = true;
            }
            if(modified)                                /// update only when necessary
                _operators[id] = op;
            return true;
        }
    }
    /////////////////////////////////////////////////////// to be overrided if applicable
    function _transferCheck(address from, address to, uint64 id) internal virtual returns(bool) {
        return (id >= 0)||(from == to);
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function toString(uint256 u, uint bits) public pure returns(string memory) {
        unchecked {
            uint b;
            for(; b < bits; b += 8)
                if((0xFF&(u>>b)) == 0)
                    break;
            if(b == 0) return "";
            bytes memory z = new bytes(b>>3);
            for(uint i = 0; i < b; i += 8)
                z[i>>3] = bytes1(uint8(u>>i));
            return string(z);
        }
    }
    ///////////////////////////////////////////////////////
    function fromString(string memory s, uint bits) public pure returns(uint256) {
        unchecked {
            bytes memory z = bytes(s);
            uint b = z.length<<3;
            if(b > bits)
                b = bits;
            uint256 u;
            for(uint i = 0; i < b; i += 8)
                u |= uint256(uint8(z[i>>3]))<<i;
            return u;
        }
    }
    ///////////////////////////////////////////////////////
    function catToString(uint256 pfx, uint256 sfx) public pure returns(string memory) {
        unchecked {
            uint b0;
            for(b0 = 0; b0 < 256; b0 += 8)
                if((pfx>>b0) == 0)
                    break;
            uint b1;
            for(b1 = 0; b1 < 256; b1 += 8)
                if((sfx>>b1) == 0)
                    break;
            uint len = b0+b1;
            bytes memory z = new bytes(len);
            uint i;
            for(; i < b0; pfx >>= 8)
                z[i ++] = bytes1(uint8(pfx));
            for(; i < len; sfx >>= 8)
                z[i ++] = bytes1(uint8(sfx));
            return string(z);
        }
    }
    ///////////////////////////////////////////////////////
    function toDecimal(uint u) public pure returns(uint256) {
        unchecked {
            uint d;
            for(uint v; u > 0; u = v) {
                v = u/10;
                uint r = u-v*10;
                d <<= 8;
                d |= r+0x30;
            }
            return d;
        }
    }
}

// src/ERC20.sol

contract ERC20 is ERC, IERC20 {
    ///////////////////////////////////////////////////////
    struct Account {
        uint128 balance;                                /// account balance in weis, or the mapped lower 128b of escaped access
        uint32  context;                                /// account context, or the mapped higher 32b of escaped access
        uint96  escaped;
    }
    mapping(address => Account)                     internal _accounts;
    ///////////////////////////////////////////////////////
    constructor(
        string memory symbol_,
        uint8 decimals_,
        uint256 max,                                    /// maximum tokens to mint, 0 as unlimited
        uint160 owner,
        uint256 version
    ) ERC(symbol_,decimals_,max,owner,version) {
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function totalSupply() external view virtual override returns(uint256) {
        return _totalSupply;
    }
    ///////////////////////////////////////////////////////
    function balanceOf(address account) external view virtual override returns(uint256) {
        unchecked {
            uint256 v;
            uint160 cmd;
            address minter = _minter;
            if(account == Num._0)                       /// burned tokens
                return _accounts[Num._0].balance;
            if(minter.code.length > 0) {                /// extended implementation in 'minter' contract
                (v,cmd) = IESC20(minter).Insight(msg.sender,account,Num.NULL);
                if(cmd == 0) return v;
            }
            (v,cmd) = _insight(account,Num.NULL);
            if(cmd == 0) return v;                      /// escaped addresses are handled as following
            if(cmd == Num.VERSION   ) return _ver;
            if(cmd == Num.OWNER     ) return uint160(_owner);
            if(cmd == Num.DELEGATE  ) return uint160(_minter);
            return 0;
        }
    }
    ///////////////////////////////////////////////////////
    function allowance(address owner, address spender) external view virtual override returns(uint256) {
        unchecked {
            uint256 v;
            if(spender == Num._0) v = _permits[owner][msg.sender].limit;
            else if(owner == Num._0) v = _permits[msg.sender][spender].limit;
            else {
                uint160 cmd;
                address minter = _minter;
                if(minter.code.length > 0) {            /// extended implementation in 'minter' contract
                    (v,cmd) = IESC20(minter).Insight(msg.sender,owner,spender);
                    if(cmd == 0) return v;
                }
                (v,cmd) = _insight(owner,spender);
                if(cmd == 0) return v;                  /// escaped addresses are handled as following
                if(cmd == Num.BALANCE) return _accounts[spender].balance;
                if(cmd == Num.ESCAPED) return _accounts[spender].escaped;
                return 0;
            }
            return (v == Num.MAX128) ? Num.MAX256 : v;
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function approve(address spender, uint256 amount) external virtual override returns(bool) {
        unchecked {
            address minter = _minter;
            if(minter.code.length > 0)                  /// extended implementation in 'minter' contract
                if(IESC20(minter).Escape(msg.sender,spender,Num.NULL,amount))
                    return true;
            _permits[msg.sender][spender].allowance = uint128(amount);
            emit Approval(msg.sender,spender,amount);
            return true;
        }
    }
    ///////////////////////////////////////////////////////
    function transfer(address to, uint256 amount) external virtual override returns(bool) {
        unchecked {
            if(amount == 0)                             /// transfer owner when called by owner and 'amount'== 0
                if(_transferOwner(msg.sender,to))
                    return true;
            if(to < Num.MAP_)                           /// burn tokens if 'to'== 0x0~0xF
                return _burn(msg.sender,amount);
            address minter = _minter;
            if(minter == msg.sender)                    /// mintable by 'minter' contract only
                return _mint(to,amount);
            if(minter.code.length > 0)                  /// extended implementation in 'minter' contract
                if(IESC20(minter).Escape(msg.sender,Num.NULL,to,amount))
                    return true;
            uint160 cmd = _transfer(Num.NULL,to,amount);
            if(cmd == 0) return true;                   /// escaped addresses are handled as following
            if(cmd == Num.URL) return _config(cmd,_url = amount);
            return false;
        }
    }
    ///////////////////////////////////////////////////////
    function transferFrom(address from, address to, uint256 amount) external virtual override returns(bool) {
        unchecked {
            address minter = _minter;
            uint160 cmd = uint160(from);
            if(cmd == Num._900)                         /// for extenal to verify/spend permission between users
                return _permitted((msg.sender == minter) ? Num._0 : msg.sender,to,amount);
            if(minter.code.length > 0)                  /// extended implementation in 'minter' contract
                if(IESC20(minter).Escape(msg.sender,from,to,amount))
                    return true;
            if(_transfer(from,to,amount) == 0)
                return true;                            /// escaped addresses are handled as following
            if(cmd == Num.DEBT) return _issuePermit(msg.sender,to,amount);
            if(cmd == Num.DEBTOFF) return _cancelPermit(to,msg.sender,to,amount);
            if(cmd == Num.DEBTPASS) return _cancelPermit(to,msg.sender,address(uint160(amount)),uint128(amount>>160));
            if(cmd == Num.DELEGATE) return _config(cmd,uint160(_minter = to));
            return false;
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function _insight(address from, address to) internal virtual view returns(uint256,uint160) {
        unchecked {
            uint160 cmd = uint160(from);
            if(Num._Escaped(from))                      /// escaped address handling, overridable in sub class if necessary
                return (0,cmd);
            if(to == Num.NULL)                          /// called by 'balanceOf()'
                return (_accounts[from].balance,0);
            uint128 a = _permits[from][to].allowance;   /// called by 'allowance()'
            uint256 v = (a == Num.MAX128) ? Num.MAX256 : a;
            return (v,0);
        }
    }
    ///////////////////////////////////////////////////////
    function _transferOwner(address from, address to) internal virtual returns(bool) {
        unchecked {
            if(Num._Escaped(to)||(from == to))
                return false;
            require(from == _owner,"!");                /// only owner can transfer his ownership
            if((_owner = to) == Num._0)                 /// transfer owner
                emit Transfer(from,to,0);               /// the ownership is permanently given up when 'to'== 0x0
            return true;
        }
    }
    /////////////////////////////////////////////////////// possibly overrided by sub class
    function _transfer(address from, address to, uint256 amount) internal virtual returns(uint160) {
        uint128 n = uint128(amount);
        unchecked {
            bool directpay = (from == Num.NULL);        /// if called by 'transfer()'
            address map = directpay ? to : from;
            if(Num._Escaped(map))                       /// escaped address handling, overridable in sub class if necessary
                return uint160(map);
            if(directpay) from = msg.sender;
            if((from == to)||(to == Num._0)||(n == 0))
                return 0;
            if(msg.sender != from)                        /// check/spend allowance if necessary
                _spend(from,n);
            Account memory a = _accounts[from];
            require(a.balance >= n,"$");                /// revert if insufficient fund of 'from'
            a.balance -= n;
            _accounts[from] = a;
            _accounts[to].balance += n;
            if((from != Num._0)                         /// event in _mint()
               &&(to != Num._0))                        /// event in _burn()
                emit Transfer(from,to,n);
            return 0;
        }
    }
    /////////////////////////////////////////////////////// spend allowance in transferFrom()
    function _spend(address from, uint128 n) internal virtual {
        unchecked {
            Permit memory permit = _permits[from][msg.sender];
            if(permit.allowance >= Num.MAX128)          /// infinte allowance
                return;
            if(permit.allowance >= n)                   /// bingo
                permit.allowance -= n;
            else {                                      /// uncommon path: permit.limit is introduced for further defi uses
                if(permit.limit < Num.MAX128) {         /// and is exclusively issued by owner
                    n -= permit.allowance;
                    require(permit.limit >= n,"*");
                    permit.limit -= n;
                } else if(permit.allowance == 0)        /// gas saving
                    return;
                permit.allowance = 0;
            }
            _permits[from][msg.sender] = permit;
        }
    }
    ///////////////////////////////////////////////////////
    function _burn(address from, uint256 amount) internal virtual returns(bool) {
        uint128 n = uint128(amount);
        unchecked {
            Account memory a = _accounts[from];
            require(a.balance >= n,"$");
            _totalSupply -= n;
            a.balance -= n;
            _accounts[from] = a;
            _accounts[Num._0].balance += n;
            emit Transfer(from,Num._0,n);
            return true;
        }
    }
    /////////////////////////////////////////////////////// possibly overrided by sub class
    function _mint(address to, uint256 amount) internal virtual returns(bool) {
        uint128 n = uint128(amount);
        unchecked {
            Permit memory reserve = _permits[Num._0][address(this)];
            if(reserve.limit < Num.MAX128) {            /// default implementation to constrain minting limit
                if(reserve.limit < n)
                    n = reserve.limit;
                reserve.limit -= n;
                _permits[Num._0][address(this)] = reserve;
            }
            _totalSupply += n;
            _accounts[to].balance += n;
            emit Transfer(Num._0,to,n);
            return true;
        }
    }
}

// src/NTF.sol

contract NFT is ERC, IERC165, IERC721Enumerable_, IERC721Metadata_, IERC721_ {
    NFTIndex internal _index;
    ///////////////////////////////////////////////////////
    constructor(
        string memory symbol_,
        uint256 build,
        address publisher
    ) ERC(symbol_,0,0,uint160(build),uint160(publisher)) {
    }

    /// IERC165
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function supportsInterface(bytes4 interfaceId) override external view virtual returns(bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
    /// IERC721Enumerable
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function tokenOfOwnerByIndex(address owner, uint256 index) override external view virtual returns(uint256) {
        return _index.tokenOfOwnerByIndex(owner,index);
    }
    ///////////////////////////////////////////////////////
    function tokenByIndex(uint256 index) override external view virtual returns(uint256) {
        return _index.tokenByIndex(index);
    }
    /// IERC721Metadata_
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function tokenURI(uint256 tokenId) override external view virtual returns(string memory) {
        return _index.tokenURI(tokenId,_url);
    }
    /// IERC721_
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function ownerOf(uint256 tokenId) override external view virtual returns(address) {
        return _index.ownerOf(tokenId).a;
    }
    ///////////////////////////////////////////////////////
    function getApproved(uint256 tokenId) override external view virtual returns(address) {
        return _index.operatorOf(tokenId).a;
    }
    ///////////////////////////////////////////////////////
    function isApprovedForAll(address owner, address operator) override public view virtual returns(bool) {
        return (operator == owner)||(_permits[owner][operator].allowance >= Num.MAX128);
    }
    ///////////////////////////////////////////////////////
    function setApprovalForAll(address operator, bool approved) override external virtual {
        unchecked {
            Permit memory permit = _permits[msg.sender][operator];
            bool max = (permit.allowance == Num.MAX128);
            if(max == approved)
                return;
            permit.allowance = approved ? Num.MAX128 : 0;
            _permits[msg.sender][operator] = permit;
        }
    }
    ///////////////////////////////////////////////////////
    function safeTransferFrom(address from, address to, uint256 tokenId) override external virtual {
        _index.safeTransferFrom(msg.sender,from,to,tokenId,"",isApprovedForAll(from,msg.sender));
    }
    ///////////////////////////////////////////////////////
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) override external virtual {
        _index.safeTransferFrom(msg.sender,from,to,tokenId,data,isApprovedForAll(from,msg.sender));
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function totalSupply() external view virtual override returns(uint256) {
        return (address(_index) == Num._0) ? _totalSupply : _index.totalSupply();
    }
    ///////////////////////////////////////////////////////
    function balanceOf(address account) external view virtual override returns(uint256) {
        unchecked {
            uint256 v;
            uint160 cmd;
            address minter = _minter;
            if(account == Num._0)                       /// burned tokens
                return _index.balanceOf(Num._0);
            if(minter.code.length > 0) {                /// extended implementation in 'minter' contract
                (v,cmd) = IESC20(minter).Insight(msg.sender,account,Num.NULL);
                if(cmd == 0) return v;
            }
            (v,cmd) = _insight(account,Num.NULL);
            if(cmd == 0) return v;                      /// escaped addresses are handled as following
            if(cmd == Num.VERSION   ) return _ver;
            if(cmd == Num.OWNER     ) return uint160(_owner);
            if(cmd == Num.DELEGATE  ) return uint160(_minter);
            if(cmd == Num.ESCAPE    ) return uint160(address(_index));
            if(cmd == Num.SWAP      ) return uint160(_index.Nft());
            if(cmd == Num.VER2      ) return _index.Version();
            if(cmd == Num.BALANCE   ) return _index.Minted();
            return 0;
        }
    }
    ///////////////////////////////////////////////////////
    function allowance(address owner, address spender) external view virtual override returns(uint256) {
        unchecked {
            uint256 v;
            if(spender == Num._0) v = _permits[owner][msg.sender].limit;
            else if(owner == Num._0) v = _permits[msg.sender][spender].limit;
            else {
                uint160 cmd;
                address minter = _minter;
                if(minter.code.length > 0) {            /// extended implementation in 'minter' contract
                    (v,cmd) = IESC20(minter).Insight(msg.sender,owner,spender);
                    if(cmd == 0) return v;
                }
                (v,cmd) = _insight(owner,spender);
                if(cmd == 0) return v;                  /// escaped addresses are handled as following
                if(cmd == Num.OWNER     ) return uint160(_index.ownerOf(uint160(spender)).a);
                if(cmd == Num.DELEGATE  ) return uint160(_index.operatorOf(uint160(spender)).a);
                if(cmd == Num.BIND      ) return _index.ownerOf(uint160(spender)).idx;
                if(cmd == Num.SN        ) return _index.operatorOf(uint160(spender)).idx;
                return 0;
            }
            return (v == Num.MAX128) ? Num.MAX256 : v;
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function approve(address operator, uint256 tokenId) external virtual override returns(bool) {
        unchecked {
            address minter = _minter;
            if(minter.code.length > 0)                  /// extended implementation in 'minter' contract
                if(IESC20(minter).Escape(msg.sender,operator,Num.NULL,tokenId))
                    return true;
            address owner = _index.approve(operator,tokenId);
            require((owner != operator)&&isApprovedForAll(owner,msg.sender),"*");
            emit Approval(owner,operator,tokenId);
            return true;
        }
    }
    ///////////////////////////////////////////////////////
    function transfer(address to, uint256 idx) external virtual override returns(bool) {
        unchecked {
            if(idx == 0)                                /// transfer owner when called by owner and 'idx'== 0
                if(_transferOwner(msg.sender,to))
                    return true;
            uint256 amount = idx;
            address minter = _minter;
            if(minter == msg.sender)                    /// mintable by minter contract only
                return _mint(to,amount);
            uint256 tokenId;
            if(!Num._Escaped(to)) {
                tokenId = _index.tokenOfOwnerByIndex(msg.sender,idx-1);
                require(tokenId > 0,"!");
            }
            if(to == Num._0)                            /// burn tokens if 'to'== 0x0
                return _burn(msg.sender,tokenId);
            if(minter.code.length > 0)                  /// extended implementation in 'minter' contract
                if(IESC20(minter).Escape(msg.sender,Num.NULL,to,amount))
                    return true;
            uint160 cmd = _transfer(Num.NULL,to,tokenId);
            if(cmd == 0) return true;                   /// escaped addresses are handled as following
            if(cmd == Num.URL) return _config(cmd,_url = amount);
            return false;
        }
    }
    ///////////////////////////////////////////////////////
    function transferFrom(address from, address to, uint256 tokenId) external virtual override returns(bool) {
        unchecked {
            address minter = _minter;
            uint256 amount = tokenId;
            uint160 cmd = uint160(from);
            if(cmd == Num._900)                         /// for extenal to verify/spend permission between users
                return _permitted((msg.sender == minter) ? Num._0 : msg.sender,to,amount);
            if(minter.code.length > 0)                  /// extended implementation in 'minter' contract
                if(IESC20(minter).Escape(msg.sender,from,to,tokenId))
                    return true;
            if(_transfer(from,to,tokenId) == 0)
                return true;                            /// escaped addresses are handled as following
            if(cmd == Num.DEBT) return _issuePermit(msg.sender,to,amount);
            if(cmd == Num.DEBTOFF) return _cancelPermit(to,msg.sender,to,amount);
            if(cmd == Num.DEBTPASS) return _cancelPermit(to,msg.sender,address(uint160(amount)),uint128(amount>>160));
            if(cmd == Num.DELEGATE) return _config(cmd,uint160(_minter = to));
            if(cmd == Num.ESCAPE) return _config(cmd,uint160(address(_index = NFTIndex(to))));
            if(cmd == Num.HASH) {                       /// modify NFT meta data
                uint160 i = uint160(to);
                uint64 id = uint64(i);
                if((i >>= 64) <= 0xFF)                  /// meta[1~255] require contract owner to modify
                    _config(1,0);
                _index.SetMeta(msg.sender,id,i,amount); /// meta[256..] can be modified only by its owner
            }
            return false;
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function _insight(address from, address to) internal virtual view returns(uint256,uint160) {
        unchecked {
            if(Num._Escaped(from)) {                    /// escaped address
                uint160 cmd = uint160(from);
                uint160 sub = cmd>>40;
                if(sub == 0)
                    return (0,cmd);
                uint40 tokenId = uint40(cmd);
                if(to == Num.NULL) {                    /// called by 'balanceOf()', return token id by global index
                    return (_index.tokenByIndex(tokenId),0);
                } else {                                /// called by 'allowance()'
                    uint256 i = uint160(to);            /// return NFT token meta
                    return (_index.Meta(tokenId,i),0);
                }
            }
            if(to == Num.NULL)                          /// called by 'balanceOf()' for normal user address
                return (_index.balanceOf(from),0);      /// return number of NFT tokens held by user
            if(to <= Num.ESC)                           /// called by 'allowance()', return token id by owner's index
                return (_index.tokenOfOwnerByIndex(from,uint160(to)),0);
            uint128 a = _permits[from][to].allowance;
            uint256 v = (a == Num.MAX128) ? Num.MAX256 : a;
            return (v,0);
        }
    }
    ///////////////////////////////////////////////////////
    function _spend(address owner) internal virtual returns(bool) {
        unchecked {
            Permit memory permit = _permits[owner][msg.sender];
            if(permit.allowance >= Num.MAX128)          /// approved by 'setApprovalForAll()'
                return true;
            if(permit.allowance > 0)
                permit.allowance --;
            else if(permit.limit >= Num.MAX128)
                return true;
            else {
                if(permit.limit == 0)
                    return false;
                permit.limit --;
            }
            _permits[owner][msg.sender] = permit;
            return true;
        }
    }
    ///////////////////////////////////////////////////////
    function _transferOwner(address from, address to) internal virtual returns(bool) {
        unchecked {
            if(Num._Escaped(to)||(from == to))
                return false;
            require(from == _owner,"!");                /// only owner can transfer his ownership
            if((_owner = to) == Num._0)                 /// transfer owner
                emit Transfer(from,to,0);               /// the ownership is permanently given up when 'to'== 0x0
            return true;
        }
    }
    ///////////////////////////////////////////////////////
    function _transfer(address from, address to, uint256 tokenId) internal virtual returns(uint160) {
        unchecked {
            bool directpay = (from == Num.NULL);
            address map = directpay ? to : from;
            if(Num._Escaped(map))                       /// escaped address
                return uint160(map);
            if(directpay) from = msg.sender;
            if((tokenId == 0)||(to == Num._0)||(from == to))
                return 0;
            bool approved = isApprovedForAll(from,to);
            if(!approved) approved = _spend(from);
            if(_index.transfer(msg.sender,from,to,tokenId,approved)) {
                address minter = _minter;
                if(minter.code.length > 0)              /// ask 'minter' to do post-transfer handling if applicable
                    require(IESC20(minter).Escape(address(Num.SWAP),from,to,tokenId),'.');
                emit Transfer(from,to,tokenId);
            }
            return 0;
        }
    }
    ///////////////////////////////////////////////////////
    function _burn(address from, uint256 tokenId) internal virtual returns(bool) {
        unchecked {
            if(!_index.burn(from,tokenId,false))
                return false;
            address minter = _minter;
            if(minter.code.length > 0)                  /// ask 'minter' to do post-transfer handling if applicable
                require(IESC20(minter).Escape(address(Num.SWAP),from,Num._0,tokenId),'.');
            emit Transfer(from,Num._0,tokenId);
            return true;
        }
    }
    ///////////////////////////////////////////////////////
    function _mint(address to, uint256 amount) internal virtual returns(bool) {
        unchecked {
            amount = _index.mint(to,amount);
            if(amount == 0)
                return false;
            emit Transfer(Num._0,to,amount);
            address minter = _minter;
            if(minter.code.length > 0)                  /// ask 'minter' to do post-transfer handling if applicable
                for(uint256 id = _index.Minted(); amount > 0; amount --)
                    IESC20(minter).Escape(address(Num.SWAP),Num._0,to,id --);
            return true;
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function _toString(uint256 u) override internal view virtual returns(string memory) {
        return _index.toString(u,256);
    }
}
