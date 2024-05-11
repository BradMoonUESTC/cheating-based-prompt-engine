// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract MemeToken is ERC20 {

    /// @dev Same TotalSupply  100,000,000
    uint256 constant TOTAL_SUPPLY = 100000000E18;
    address immutable public FACTORY;
    bool internal isInitialized;
    address public mainPool;


    //////////////////////////////// Errors ////////////////////////////////

    error DuplicateInitialization();
    error NotPool();


    //////////////////////////////// Init ////////////////////////////////

    constructor(string memory symbol) ERC20("MEME", symbol) {
        FACTORY = msg.sender;
    }


    //////////////////////////////// Events ////////////////////////////////

    event InitializeToken(address pool);


    //////////////////////////////// Modifiers ////////////////////////////////

    modifier onlyPool() {
        if (msg.sender != mainPool) { revert NotPool(); }
        _;
    }

    /// @notice Init Mint Token To Pool
    /// @param pool, Pool Address
    function initialize(address pool) external {
        if (isInitialized) { revert DuplicateInitialization(); }
        mainPool = pool;
        _mint(pool, TOTAL_SUPPLY);
        isInitialized = true;
        emit InitializeToken(pool);
    }

    /// @notice Transfer Token to Pool without Approve
    /// @param user, the token holder who addLiq or Sell Token
    /// @param amount, token amount
    function transferByPool(
        address user,
        uint256 amount
    ) onlyPool external {
        _transfer(user, mainPool, amount);
    }

}

contract TokenFactory {

    /// @notice Deploy Token
    /// @param symbol, Token symbol
    function deploy(
        string calldata symbol
    ) external returns (address tokenAddress) {
        tokenAddress = address(new MemeToken(symbol));
    }

}
