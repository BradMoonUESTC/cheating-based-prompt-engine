// SPDX-License-Identifier: GPL-3.0
pragma solidity <0.9.0 >=0.7.0;

// src/IDeflate.sol

library _Deflate {
    ///////////////////////////////////////////////////////
    uint160 public constant TAX         =   0xDF00;
    uint160 public constant CTX         =   0xDF01;
    uint160 public constant DEV         =   0xDF02;
    uint160 public constant FACTORY     =   0xDF03;
    uint160 public constant MINT        =   0xDF04;
    uint160 public constant MEMBER      =   0xDF05;
    ///////////////////////////////////////////////////////
    uint160 public constant PROMOTE     =   0xDF10;
    uint160 public constant GROWTH      =   0xDF11;
    uint160 public constant CAP         =   0xDF12;
    uint160 public constant MIN         =   0xDF13;
    uint160 public constant Y2TAX       =   0xDF14;
    uint160 public constant U2TAX       =   0xDF15;
    ///////////////////////////////////////////////////////
    uint160 public constant CLOCK       =   0xFF00;
    uint160 public constant CLOCKED     =   0xFF01;
    uint160 public constant UNSTAKE     =   0xFF02;
    uint160 public constant RESTAKE     =   0xFF03;
    ///////////////////////////////////////////////////////
    uint160 public constant HP          =   0xFF10;
    uint160 public constant PRICE       =   0xFF11;
    uint160 public constant LEFT        =   0xFF12;
    uint160 public constant PRIVILEDGE  =   0xFF13;
    ///////////////////////////////////////////////////////
    uint160 public constant MINT2BURN   =   0xFF20;
    uint160 public constant REFERRER    =   0xFF21;
    uint160 public constant EN2BURN     =   0xFF22;
    uint160 public constant ENHANCE     =   0xFF23;
    uint160 public constant TOGAS       =   0xFF24;
    uint160 public constant MAXBUY      =   0xFF25;
    uint160 public constant MINGAS      =   0xFF26;
    ///////////////////////////////////////////////////////
    uint160 public constant NFT         =   0xFF30;
    uint160 public constant YIELD       =   0xFF31;
    uint160 public constant COMMISSION  =   0xFF32;
    ///////////////////////////////////////////////////////
    uint160 public constant VER         =   0xFFf0;
    uint160 public constant VER2        =   0xFDf0;
    uint160 public constant MARKET      =   0xFDff;
    ///////////////////////////////////////////////////////
}

interface IDeflatee {
    ///////////////////////////////////////////////////////
    function Config(uint160 cmd, uint256 amount) external returns(bool);
    function MintNft(uint64 referrer, uint64 id, uint32 hp, uint32 paid, uint32 quota) external;
    function Enhance(uint64 nftId, uint32 cents) external returns(bool);
    function Buyable(address token, uint64 nftId, uint32 cents) external returns(bool);
    function Stake(address user, uint64 nftId, uint32 cents, uint128 balance) external returns(uint128);
    function Unstake(uint64 nftId, uint256 percent) external returns(bool);
    function Restaking(uint64 nftId, uint256 amount) external returns(bool);
    function Collect(address user, uint64 nftId) external returns(bool);
    function Clock(uint n, bool onDay) external returns(uint256);
    ///////////////////////////////////////////////////////
    function Insight(uint160 cmd, address to) external view returns(uint256,uint160);
}

interface IDeflater {
    ///////////////////////////////////////////////////////
    function Balance(uint64 nftId, bool staked) external view returns(uint128);
    function Collect(address user, uint64 nftId) external returns(bool);
    function Stake(address user, uint64 nftId, uint32 cents, uint128 balance) external returns(uint128);
    function Commit(uint128 amount) external returns(address);
}

interface IDeflaterCallback {
    ///////////////////////////////////////////////////////
    function Collected(address user, uint256 amount) external returns(uint32);
    function Taxed(uint32 cents, uint subject) external returns(bool);
}

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

// src/Deflatium.sol

/////////////////////////////////////////////////////////// IUniswapV2Router01
interface ISwapRouter {
    function factoryV2() external pure returns (address);
}
/////////////////////////////////////////////////////////// IUniswapV2Factory
interface ISwapFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}
/////////////////////////////////////////////////////////// IUniswapV2Pair
interface ISwapPair {
    function sync() external;
}

library _Deflatium {
    ///////////////////////////////////////////////////////
    uint160 public constant DEFLATE     =   0xFD00;
    uint160 public constant BUY         =   0xFD01;
    uint160 public constant SELL        =   0xFD02;
    uint160 public constant BURN        =   0xFD0b;
    uint160 public constant MARKET      =   0xFDff;
    ///////////////////////////////////////////////////////
}
contract Deflatium is ERC20 {
    ///////////////////////////////////////////////////////
    struct Dex {
        address lp;                                     /// LP token of UniSwap/PancakeSwap
        uint16  deflateDaily;                           /// 32768 = 50%: per collecting by _minter
        uint16  deflatePerBuy;                          /// 32768 = 50%: per buy
        uint16  deflatePerSell;                         /// 32768 = 50%: per sell
        uint8   burnPerDeflate;                         /// 128   = 50%: burn/deflation
        uint8   daysToMarket;                           /// non-nft-holders can buy this token after market is opened
    }
    Dex     internal  _dex;
    ///////////////////////////////////////////////////////
    constructor(
        string memory symbol_,
        address router,                                 /// UniSwap/PancakeSwap
        address usd,                                    /// USDT/USDC
        uint256 total,                                  /// no more than 40M
        uint8 daysToMarket,                             /// day count to open market
        uint256 build,
        address publisher
    ) ERC20(symbol_,18,0,uint160(build),uint160(publisher)) {
        unchecked {
            Dex memory dex;
            if(router.code.length > 0)
                dex.lp = ISwapFactory(ISwapRouter(router).factoryV2()).createPair(address(this),usd);
            dex.deflateDaily    = uint16(uint(15)*0x10000/1000);    /// DEX pool defaltes 1.5% per day
            dex.deflatePerBuy   = uint16(uint( 3)*0x10000/100);     /// every buy  defaltes 3%
            dex.deflatePerSell  = uint16(uint( 3)*0x10000/100);     /// every sell defaltes 3%
            dex.burnPerDeflate  = uint8 (uint(256)/3);  /// burn 1/3 of total deflation
            dex.daysToMarket    = daysToMarket;
            _dex = dex;
            _accounts[msg.sender].balance = uint128(_totalSupply = total*Num._1);
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function balanceOf(address account) external view virtual override returns(uint256) {
        unchecked {
            if(account == Num._0)                       /// burned tokens
                return _accounts[Num._0].balance;
            uint256 v;
            uint160 cmd;
            address minter = _minter;
            if(account > Num.ESC) {                     /// normal addresses
                Account memory a = _accounts[account];
                if(account == _dex.lp)                  /// 'lp.escaped' temporally holds the tokens to be burned or transferred to NFT
                    return a.balance-a.escaped;
                if(account == minter)                   
                    return a.balance;
                if(a.escaped > 0) {                     /// NFT holders
                    uint40 nftId = uint40(a.escaped);   /// plus tokens (staked and yield) in NFT
                    v = IDeflater(minter).Balance(nftId,true);
                }
                return v+a.balance;
            }
            //@audit no use
            (v,cmd) = _insight(account,Num.NULL);
            if(cmd == 0) return v;                      /// escaped addresses are handled as following
            if(cmd == Num.VERSION       ) return _ver;
            if(cmd == Num.OWNER         ) return uint160(_owner);
            if(cmd == Num.DELEGATE      ) return uint160(minter);
            if(cmd == Num.BIND          ) return uint160(_dex.lp);
            if(cmd == Num.ESCAPE        ) return IDeflater(minter).Balance(0,true); /// total staked tokens for NFT contract
            if(cmd == _Deflatium.MARKET ) return _dex.daysToMarket*Num._1;
            uint256 per;
            if(cmd == _Deflatium.DEFLATE) per = _dex.deflateDaily;   else
            if(cmd == _Deflatium.BUY    ) per = _dex.deflatePerBuy;  else
            if(cmd == _Deflatium.SELL   ) per = _dex.deflatePerSell; else
            if(cmd == _Deflatium.BURN   ) per = uint(_dex.burnPerDeflate)<<8; else
                return 0;
            return (per*Num._100)>>16;
        }
    }
    ///////////////////////////////////////////////////////
    function allowance(address owner, address spender) external view virtual override returns(uint256) {
        unchecked {
            uint256 v;
            //@audit spender == address(0) v = msg.sender limit of owner
            if(spender == Num._0) v = _permits[owner][msg.sender].limit;
            else if(owner == Num._0) v = _permits[msg.sender][spender].limit;
            else if(owner > Num.ESC) v = _permits[owner][spender].allowance;
            else {
                uint160 cmd;
                address minter = _minter;
                (v,cmd) = _insight(owner,spender);
                if(cmd == 0) return v;                  /// escaped addresses are handled as following
                if(cmd == Num.ESCAPED) return _accounts[spender].escaped;
                if(cmd == Num.BALANCE) {
                    Account memory a = _accounts[spender];
                    if((a.escaped > 0)&&(spender > Num.ESC)&&(spender != minter)) {
                        uint40 nftId = uint40(a.escaped);
                        v = IDeflater(minter).Balance(nftId,false);
                    }
                    return v+a.balance;
                }
                return 0;
            }
            return (v == Num.MAX128) ? Num.MAX256 : v;
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function approve(address spender, uint256 amount) external virtual override returns(bool) {
        unchecked {
            address minter = _minter;
            if(msg.sender == minter) {
                Account memory a = _accounts[spender];
                uint128 leftover = uint128(amount>>128);
                uint40 nftId = uint40(amount);          /// update NFT id held by user
              //@audit approve 为什么要有余额变动操作
                if(leftover > 0) {                      /// return fund temporally held in minter contract (staked or leftover)
                    _accounts[minter].balance -= leftover;
                    a.balance += leftover;
                }
                a.escaped = nftId;
                _accounts[spender] = a;
                return true;
            }
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
            uint160 cmd = _transfer(Num.NULL,to,amount);
            if(cmd == 0) return true;                   /// escaped addresses are handled as following
            uint16 per = uint16((amount<<16)/Num._100);
            if(cmd == Num.URL           ) _url = amount; else
            if(cmd == _Deflatium.MARKET ) _dex.daysToMarket   = uint8(amount/Num._1); else
            if(cmd == _Deflatium.BURN   ) _dex.burnPerDeflate = uint8 (per>>8); else
            if(cmd == _Deflatium.BUY    ) _dex.deflatePerBuy  = per; else
            if(cmd == _Deflatium.SELL   ) _dex.deflatePerSell = per; else
            if(cmd == _Deflatium.DEFLATE) _dex.deflateDaily   = per; else
                return false;
            return _config(cmd,0);                      /// require ownership to config (as above)
        }
    }
    ///////////////////////////////////////////////////////
    function transferFrom(address from, address to, uint256 amount) external virtual override returns(bool) {
        unchecked {
            uint160 cmd = uint160(from);
            if(cmd == Num._900)                         /// for extenal to verify/consume permission between users
                return _permitted((msg.sender == _minter) ? Num._0 : msg.sender,to,amount);
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
    function _insight(address from, address to) override internal virtual view returns(uint256,uint160) {
        return (0,uint160(to = from));
    }
    ///////////////////////////////////////////////////////
    function _transfer(address from, address to, uint256 amount) override internal virtual returns(uint160) {
        uint128 n = uint128(amount);
        unchecked {
            bool directpay = (from == Num.NULL);
            address map = directpay ? to : from;
            if(Num._Escaped(map))                       /// mapped address (not normal user)
                return uint160(map);
            if(directpay) from = msg.sender;
            if(to == Num._0)
                return 0;
            if(msg.sender != from)
                _spend(from,n);                         /// check/spend allowance
            Dex memory dex = _dex;
            address minter = _minter;
            if(to == minter) {                          /// special cases to handle
                if(msg.sender == minter) return _Deflating(dex,minter,n > 0);
                if(from != dex.lp) return _Stake(from,minter,n);
            }
            Account memory a = _accounts[from];
            uint128 balance = (from == dex.lp) ? a.balance-a.escaped : a.balance;
            if(balance < n) {
                uint64 nftId = uint64(a.escaped);
                if((nftId > 0)                          /// NFT holder
                 &&(from > Num.ESC)                     /// from normal address
                 &&(from != minter)                     /// excpet minter/lp
                 &&(from != dex.lp))                    /// reallocate tokens (if any) from NFT
                    if(IDeflater(minter).Collect(from,nftId))
                        balance = (a = _accounts[from]).balance;
                require(balance >= n,"$");
            }
            Account memory b = _accounts[to];
            if(to == dex.lp) {
                require(dex.daysToMarket == 0,"*");     /// not sellable before market is opened
                if(n < (b.balance-b.escaped)) {
                    uint96 deflated = uint96((n*dex.deflatePerSell)>>16);
                    b.escaped += deflated;              /// deflation per sell, held in 'lp.escaped' temporally to save gas
                }
            }
            else if(from == dex.lp) {
                if(to != minter) {
                    require(dex.daysToMarket == 0,"*"); /// only NFT holder can buy limited amount of tokens before market is opened
                    uint96 deflated = uint96((n*dex.deflatePerBuy)>>16);
                    a.escaped += deflated;              /// deflation per buy, held in 'lp.escaped' temporally to save gas
                    n -= deflated;
                }
            }
            a.balance -= n;
            b.balance += n;
            _accounts[to] = b;
            _accounts[from] = a;
            if((from != Num._0)                         /// event in _mint()
               &&(to != Num._0))                        /// event in _burn()
                emit Transfer(from,to,n);
            return 0;
        }
    }
    ///////////////////////////////////////////////////////
    function _mint(address to, uint256 amount) override internal virtual returns(bool) {
        require((amount = uint160(to)) < 0,"");         /// shall NOT be called! this is not a mintable token!
        return false;
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function _Deflating(Dex memory dex, address minter, bool mint) internal virtual returns(uint160) {
        unchecked {                                     /// NFT contract calls 'transfer(NFT contract, 1)' to collect daily deflation
            Account memory a = _accounts[dex.lp];
            uint256 deflate = ((a.balance-a.escaped)*dex.deflateDaily)>>16;
            uint128 burn = uint128(mint ? (deflate*dex.burnPerDeflate)>>8 : deflate);
            _burn(dex.lp,burn);
            if((a.escaped > 0)&&(minter.code.length > 0)) {
                address bank = IDeflater(minter).Commit(a.escaped);
                _accounts[bank].balance += a.escaped;   /// claim temporally collected trading deflation
            }
            a.balance -= uint128(deflate+a.escaped);
            a.escaped = 0;
            _accounts[dex.lp] = a;
            ISwapPair(dex.lp).sync();
            if(mint) {
                a = _accounts[minter];
                a.escaped = uint96(deflate-burn);       /// today' yield
                a.balance += a.escaped;                 /// transfer rest of deflation to NFT contract
                _accounts[minter] = a;
            }
            if(dex.daysToMarket > 0) {
                dex.daysToMarket --;                    /// count down
                _dex = dex;
            }
            return 0;
        }
    }
    /////////////////////////////////////////////////////// NFT holder may call 'transfer(NFT contract, amount)' to stake
    function _Stake(address user, address minter, uint256 amount) internal virtual returns(uint160) {
        uint32 cents = uint32(amount/Num._0_01);
        unchecked {
            Account memory a = _accounts[user];
            require(a.escaped > 0,"%");                 /// only NFT holder can stake
            uint128 leftover = IDeflater(minter).Stake(user,uint40(a.escaped),cents,a.balance);
            if(leftover == 0)                           /// fully staked within NFT, no more leftover
                return 0;
            a.balance -= leftover;                      /// transfer leftover to NFT contract
            _accounts[minter].balance += leftover;
            _accounts[user] = a;
            return 0;
        }
    }
}
