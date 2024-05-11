// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IMemeToken.sol";
import "./interfaces/IModule.sol";
import "./interfaces/ITokenFactory.sol";


contract MemePool is ERC20 {

    /// @dev DEFAULT LIQUIDITY TODO Pre-deployment decision
    uint256 constant START_LIQUIDITY = 10000E18;
    /// @dev Max Fee 1%  TODO Pre-deployment decision
    uint256 constant MAX_FEE_PARAM = 10;
    /// @dev EXTRACT FROM SWAP TODO Pre-deployment decision
    uint256 constant DEV_FEE_RATE = 1; // 0.1%
    uint256 constant PRECISION = 1E3;
    address immutable public FACTORY;
    address immutable public QUOTE_TOKEN;
    uint256 immutable public FEE_PARAM;
    IModule immutable public module;
    address immutable public PLATFORM;
    // Flag
    bool immutable internal INIT_FLAG;
    bool immutable internal BEFORE_BUY_FLAG;
    bool immutable internal AFTER_BUY_FLAG;
    bool immutable internal BEFORE_SELL_FLAG;
    bool immutable internal AFTER_SELL_FLAG;
    bool immutable internal AFTER_ADD_FLAG;
    bool immutable internal AFTER_REMOVE_FLAG;

    bool internal isInitialized;


    //////////////////////////////// Errors ////////////////////////////////

    error FeeTooLarge();
    error ZeroAmount();
    error ZeroLiquidity();
    error LessThanMinReturn();
    error DuplicateInitialization();


    //////////////////////////////// INIT ////////////////////////////////

    constructor(
        address _quoteToken,
        uint256 _feeParam,
        address _module,
        address _platform
    ) ERC20('MemeLPV2', 'MLP') {
        if (_feeParam > MAX_FEE_PARAM) { revert FeeTooLarge(); }
        FACTORY = msg.sender;
        QUOTE_TOKEN = _quoteToken;
        FEE_PARAM = _feeParam;
        module = IModule(_module);
        (INIT_FLAG, AFTER_ADD_FLAG, AFTER_REMOVE_FLAG, BEFORE_BUY_FLAG, AFTER_BUY_FLAG, BEFORE_SELL_FLAG, AFTER_SELL_FLAG) = module.getFlag();
        PLATFORM = _platform;
    }


    //////////////////////////////// Events ////////////////////////////////

    event InitializePool();
    event AddLiquidity(
        address user,
        uint256 nativeIn,
        uint256 tokenIn,
        uint256 liquidity
    );
    event RemoveLiquidity(
        address user,
        uint256 nativeOut,
        uint256 tokenOut,
        uint256 liquidity
    );
    event Swap(
        address user,
        uint256 nativeIn,
        uint256 tokenIn,
        uint256 nativeOut,
        uint256 tokenOut
    );
    event FeeCollected(uint256 nativeAmount);


    /// @notice INIT Pool Lock LPToken
    function initialize() external payable returns (uint256 lockAmount) {
        if (isInitialized) { revert DuplicateInitialization(); }
        if (INIT_FLAG) {
            module.initialize();
        }
        lockAmount = START_LIQUIDITY;
        _mint(msg.sender, lockAmount);
        isInitialized = true;
        emit InitializePool();
    }

    /// @notice add Liquidity to pool
    /// @dev ALL Native In, Token Amount Based On Native
    /// @param minReturn, min return LP
    function addLiquidity(uint256 minReturn) external payable {
        address user = msg.sender;
        uint256 _totalSupply = totalSupply();
        /// @dev If _totalSupply = 0, The Pool is Useless
        if (_totalSupply == 0) { revert ZeroLiquidity(); }
        uint256 nativeIn = msg.value;
        (uint256 reserveNative, uint256 reserveToken) = getReserves();
        uint256 liquidity = nativeIn * _totalSupply / (reserveNative - nativeIn);
        if (liquidity == 0) { revert ZeroAmount(); }
        if (liquidity < minReturn) { revert LessThanMinReturn();}
        uint256 tokenIn = reserveToken * liquidity / _totalSupply + 1;
        IMemeToken(QUOTE_TOKEN).transferByPool(user, tokenIn);
        _mint(user, liquidity);
        if (AFTER_ADD_FLAG) {
            module.afterAdd(user, tokenIn, nativeIn);
        }
        emit AddLiquidity(user, nativeIn, tokenIn, liquidity);
    }

    /// @notice Remove Liquidity From Pool
    /// @param liquidity, Burn Amount
    /// @param minNative, Min Native Get
    /// @param minToken, Min Meme Token Get
    function removeLiquidity(
        uint256 liquidity,
        uint256 minNative,
        uint256 minToken
    ) external {
        address user = msg.sender;
        uint256 _totalSupply = totalSupply();
        _burn(msg.sender, liquidity);
        (uint256 reserveNative, uint256 reserveToken) = getReserves();
        uint256 nativeOut;
        uint256 tokenOut;
        if (liquidity == _totalSupply) {
            nativeOut = reserveNative;
            tokenOut = reserveToken;
        } else {
            nativeOut = liquidity * reserveNative / _totalSupply;
            tokenOut = liquidity * reserveToken / _totalSupply;
        }
        // Transfer
        if (nativeOut == 0 && tokenOut == 0) { revert ZeroAmount(); }
        if (nativeOut < minNative || tokenOut < minToken) { revert LessThanMinReturn();}
        payable(user).transfer(nativeOut);
        IMemeToken(QUOTE_TOKEN).transfer(user, tokenOut);
        if (AFTER_REMOVE_FLAG) {
            module.afterRemove(user, tokenOut, nativeOut);
        }
        emit RemoveLiquidity(user, nativeOut, tokenOut, liquidity);
    }

    /// @notice Native Token To Meme
    /// @param minReturn, Min Meme Get
    function buy(uint256 minReturn) external payable {
        uint256 nativeIn = msg.value;
        // Fee
        if (DEV_FEE_RATE > 0) {
            nativeIn = _feeCollect(nativeIn);
        }
        if (nativeIn == 0) { revert ZeroAmount(); }
        address trader = msg.sender;
        // Before Logic
        if (BEFORE_BUY_FLAG) {
            module.beforeBuy(trader, nativeIn);
        }
        // Quote
        (uint256 reserveNative, uint256 reserveToken) = getReserves();
        uint256 expectedTokenOut = _quote(nativeIn, reserveNative - nativeIn, reserveToken);
        // After Logic
        uint256 actualTokenOut = expectedTokenOut;
        if (AFTER_BUY_FLAG) {
            actualTokenOut = module.afterBuy(trader, nativeIn, expectedTokenOut);
        }
        // Check
        if (actualTokenOut == 0) { revert ZeroAmount(); }
        if (actualTokenOut < minReturn) {revert LessThanMinReturn(); }
        // Transfer
        IMemeToken(QUOTE_TOKEN).transfer(trader, actualTokenOut);
        if (actualTokenOut < expectedTokenOut) {
            IMemeToken(QUOTE_TOKEN).transfer(address(module), expectedTokenOut - actualTokenOut);
        } else if (actualTokenOut > expectedTokenOut) {
            revert();
        }
        emit Swap(trader, nativeIn, 0, 0, actualTokenOut);
    }

    /// @notice Meme To Native Token
    /// @param tokenIn, Meme In Amount
    /// @param minReturn, Min Native Get
    function sell(uint256 tokenIn, uint256 minReturn) external {
        if (tokenIn == 0) { revert ZeroAmount(); }
        address trader = msg.sender;
        // Before Logic
        if (BEFORE_SELL_FLAG) {
            module.beforeSell(trader, tokenIn);
        }
        // Quote
        (uint256 reserveNative, uint256 reserveToken) = getReserves();
        uint256 expectedTokenOut = _quote(tokenIn, reserveToken, reserveNative);
        // Fee
        if (DEV_FEE_RATE > 0) {
            expectedTokenOut = _feeCollect(expectedTokenOut);
        }
        // Transfer In
        IMemeToken(QUOTE_TOKEN).transferByPool(trader, tokenIn);
        // After Logic
        uint256 actualTokenOut = expectedTokenOut;
        if (AFTER_SELL_FLAG) {
            actualTokenOut = module.afterSell(trader, tokenIn, expectedTokenOut);
        }
        // Check
        if (actualTokenOut == 0) { revert ZeroAmount(); }
        if (actualTokenOut < minReturn) {revert LessThanMinReturn(); }
        // Transfer
        payable(trader).transfer(actualTokenOut);
        if (actualTokenOut < expectedTokenOut) {
            payable(address(module)).transfer(expectedTokenOut - actualTokenOut);
        } else if (actualTokenOut > expectedTokenOut) {
            revert();
        }
        emit Swap(trader, 0, tokenIn, actualTokenOut, 0);
    }

    /// @notice Quoter
    /// @param trader, Trader Address
    /// @param amount, AmountIn
    /// @param _buy, Buy Or Sell
    function getAmountOut(
        address trader,
        uint256 amount,
        bool _buy
    ) external view returns(uint256 amountOut) {
        (uint256 reserveNative, uint256 reserveToken) = getReserves();
        if (_buy) {
            if (DEV_FEE_RATE > 0) {
                amount = amount - amount * DEV_FEE_RATE / PRECISION;
            }
            amountOut = _quote(amount, reserveNative, reserveToken);
            if (AFTER_BUY_FLAG) {
                amountOut = _quoteBuy(trader, amount, amountOut);
            }
        } else {
            amountOut = _quote(amount, reserveToken, reserveNative);
            if (DEV_FEE_RATE > 0) {
                amountOut = amountOut - amountOut * DEV_FEE_RATE / PRECISION;
            }
            if (AFTER_SELL_FLAG) {
                amountOut = _quoteSell(trader, amount, amountOut);
            }
        }
    }

    function getReserves() public view returns (uint256, uint256) {
        return (address(this).balance, IMemeToken(QUOTE_TOKEN).balanceOf(address(this)));
    }

    function _quote(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal view returns (uint256 amountOut) {
        uint256 amountInWithFee = amountIn * (1000 - FEE_PARAM);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function _quoteBuy(
        address _trader,
        uint256 _amountIn,
        uint256 _amountOut
    ) internal view returns (uint256 amountOut) {
        amountOut = module.quoteBuy(_trader, _amountIn, _amountOut);
    }

    function _quoteSell(
        address _trader,
        uint256 _amountIn,
        uint256 _amountOut
    ) internal view returns (uint256 amountOut) {
        amountOut = module.quoteSell(_trader, _amountIn, _amountOut);
    }

    function _feeCollect(uint256 nativeAmount) internal returns (uint256) {
        uint256 feeAmount = nativeAmount * DEV_FEE_RATE / PRECISION;
        if (feeAmount > 0) {
            payable(PLATFORM).transfer(feeAmount);
            emit FeeCollected(feeAmount);
            return nativeAmount - feeAmount;
        } else {
            return nativeAmount;
        }
    }

    receive() external payable {}

}

contract PoolFactory {

    address immutable public PLATFORM;
    ITokenFactory immutable public tokenFactory;

    error AuthorizationError();

    constructor(address _platform, address _tokenFactory) {
        PLATFORM = _platform;
        tokenFactory = ITokenFactory(_tokenFactory);
    }

    modifier onlyPlatform() {
        if (msg.sender != PLATFORM) {
            revert AuthorizationError();
        }
        _;
    }

    /// @notice Deploy Pool
    /// @param symbol, Token Symbol
    /// @param feeParam, Fee Param
    /// @param module, module address
    function deploy(
        string calldata symbol,
        uint256 feeParam,
        address module
    ) onlyPlatform external returns (address poolAddress, address quoteToken) {
        // Deploy Token
        quoteToken = tokenFactory.deploy(symbol);
        poolAddress = address(new MemePool(quoteToken, feeParam, module, msg.sender));
    }

}
