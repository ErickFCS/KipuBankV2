// SPDX-License-Identifier: BSD 3-Clause
pragma solidity 0.8.30;

// Access Control and Interfaces
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title KipuBankV2
 * @notice A multi-asset vault with a USD-denominated deposit cap, protected by an owner.
 */
// Inherit Ownable for access control
contract KipuBankV2 is Ownable {
    /*///////////////////////////////////
          Type declarations
    ///////////////////////////////////*/
    /// @notice Defines the type of balance update operation.
    enum Operation {
        Extract,
        Deposit
    }

    /// @notice Defines the standard decimal unit for internal accounting (e.g., 6 for USDC).
    uint8 private constant USD_STANDARD_DECIMALS = 6;

    // address(0) will represent Native Ether (ETH)

    /*///////////////////////////////////
           Immutable variables
    ///////////////////////////////////*/
    /// @notice Total deposit value allowed, denominated in USD_STANDARD_DECIMALS.
    uint256 public immutable i_bankCapUSD;
    /// @notice Biggest value allowed for any individual extract, denominated in USD_STANDARD_DECIMALS.
    uint256 public immutable i_maxExtractUSD;
    /// @notice Instance of the Chainlink ETH/USD data feed.
    AggregatorV3Interface public immutable i_priceFeed;

    /*///////////////////////////////////
           State variables
    ///////////////////////////////////*/
    /// @notice Mapping for storing user balances: user => token address => balance.
    /// Balances are stored in the token's native decimals.
    mapping(address user => mapping(address token => uint256 balance))
        private s_accounts;

    /// @notice Total value deposited across all assets, denominated in USD_STANDARD_DECIMALS.
    uint256 public s_totalDepositsUSD;

    /*///////////////////////////////////
                Errors
    ///////////////////////////////////*/
    /// @notice Emitted when a deposit fails due to the bank cap.
    error KipuBank_FailedDeposit(
        address wallet,
        uint256 quantity,
        string reason
    );
    /// @notice Emitted when an extract fails.
    error KipuBank_FailedExtract(
        address wallet,
        uint256 quantity,
        string reason
    );
    /// @notice Emitted when a required operation fails (e.g., token transfer, oracle read).
    error KipuBank_OperationFailed(string reason);
    /// @notice Emitted when a zero value is passed.
    error KipuBank_ZeroValue();

    /*///////////////////////////////////
               Events
    ///////////////////////////////////*/
    /// @notice Emitted when there is a successful extract.
    /// @param wallet The address of the account that extracted.
    /// @param token The token address (address(0) for ETH).
    /// @param quantity The amount extracted (in token decimals).
    event KipuBank_SuccessfulExtract(
        address indexed wallet,
        address indexed token,
        uint256 quantity
    );
    /// @notice Emitted when there is a successful deposit.
    /// @param wallet The address of the account that deposited.
    /// @param token The token address (address(0) for ETH).
    /// @param quantity The amount deposited (in token decimals).
    /// @param usdValue The USD value of the deposit (in USD_STANDARD_DECIMALS).
    event KipuBank_SuccessfulDeposit(
        address indexed wallet,
        address indexed token,
        uint256 quantity,
        uint256 usdValue
    );
    /// @notice Emitted after any successful balance update.
    /// @param wallet The address of the account whose balance was updated.
    /// @param token The token address.
    /// @param newBalance The new total balance of the account (in token decimals).
    event KipuBank_SuccessfulBalanceUpdate(
        address indexed wallet,
        address indexed token,
        uint256 newBalance
    );

    /*///////////////////////////////////
                Modifiers
    ///////////////////////////////////*/
    /// @notice Verifies the bank cap limit based on USD value.
    /// @param _usdValue The USD value of the deposit to check against the cap.
    modifier underBankCap(uint256 _usdValue) {
        if (s_totalDepositsUSD + _usdValue > i_bankCapUSD)
            revert KipuBank_FailedDeposit(msg.sender, _usdValue, "Cap reached");
        _;
    }

    /*///////////////////////////////////
                Functions
    ///////////////////////////////////*/

    /*/////////////////////////
            constructor
    /////////////////////////*/
    /// @notice Sets the constraints and Chainlink Oracle address.
    /// @param _maxExtractUSD The biggest USD value allowed for an extract.
    /// @param _bankCapUSD The total bank USD limit.
    /// @param _priceFeedAddress The address of the Chainlink ETH/USD Data Feed.
    constructor(
        uint256 _maxExtractUSD,
        uint256 _bankCapUSD,
        address _priceFeedAddress
    ) Ownable(msg.sender) {
        i_maxExtractUSD = _maxExtractUSD;
        i_bankCapUSD = _bankCapUSD;
        i_priceFeed = AggregatorV3Interface(_priceFeedAddress);
    }

    /*/////////////////////////
        Receive&Fallback
    /////////////////////////*/
    /// @notice Prevents direct Ether deposits.
    receive() external payable {
        revert KipuBank_FailedDeposit(
            msg.sender,
            msg.value,
            "Use deposit function"
        );
    }

    /*/////////////////////////
            external
    /////////////////////////*/

    /// @notice Deposits Native Ether to the sender's account.
    function depositETH()
        external
        payable
        underBankCap(_getUSDValue(address(0), msg.value))
    {
        if (msg.value == 0) revert KipuBank_ZeroValue();

        // Calculate USD value and update state
        uint256 usdValue = _getUSDValue(address(0), msg.value);

        unchecked {
            s_totalDepositsUSD += usdValue;
        }

        // Use address(0) to represent ETH in the multi-token accounting
        _updateAccountBalance(address(0), msg.value, Operation.Deposit);

        // Emit event
        emit KipuBank_SuccessfulDeposit(
            msg.sender,
            address(0),
            msg.value,
            usdValue
        );
    }

    /// @notice Deposits an ERC-20 token to the sender's account. Must be pre-approved.
    /// @param _token The address of the ERC-20 token.
    /// @param _amount The amount of tokens to deposit (in token decimals).
    function depositERC20(
        address _token,
        uint256 _amount
    ) external underBankCap(_getUSDValue(_token, _amount)) {
        if (_amount == 0) revert KipuBank_ZeroValue();
        if (_token == address(0))
            revert KipuBank_OperationFailed("Use depositETH");

        // Calculate USD value and update state
        uint256 usdValue = _getUSDValue(_token, _amount);

        unchecked {
            s_totalDepositsUSD += usdValue;
        }

        _updateAccountBalance(_token, _amount, Operation.Deposit);

        // Pull token from sender
        bool success = IERC20(_token).transferFrom(
            msg.sender,
            address(this),
            _amount
        );
        if (!success) revert KipuBank_OperationFailed("Token transfer failed");

        // Emit event
        emit KipuBank_SuccessfulDeposit(msg.sender, _token, _amount, usdValue);
    }

    /// @notice Extracts either Native Ether (address(0)) or an ERC-20 token.
    /// @param _token The address of the asset (address(0) for ETH).
    /// @param _quantity The amount to extract (in token decimals).
    function extractFromAccount(address _token, uint256 _quantity) external {
        if (_quantity == 0) revert KipuBank_ZeroValue();

        // Check if quantity exceeds max extract limit in USD
        uint256 usdValue = _getUSDValue(_token, _quantity);
        if (usdValue > i_maxExtractUSD)
            revert KipuBank_FailedExtract(
                msg.sender,
                _quantity,
                "Limit exceeded"
            );

        // Check if quantity exceeds account balance in token decimals
        if (_quantity > s_accounts[msg.sender][_token])
            revert KipuBank_FailedExtract(
                msg.sender,
                _quantity,
                "Insufficient balance"
            );

        // Update state before interaction
        _updateAccountBalance(_token, _quantity, Operation.Extract);

        unchecked {
            s_totalDepositsUSD -= usdValue;
        }

        // Send asset
        bool success;
        if (_token == address(0)) {
            (success, ) = msg.sender.call{value: _quantity}("");
        } else {
            success = IERC20(_token).transfer(msg.sender, _quantity);
        }

        // Post-interaction check
        if (!success)
            revert KipuBank_FailedExtract(
                msg.sender,
                _quantity,
                "Transfer failed"
            );

        // Emit event
        emit KipuBank_SuccessfulExtract(msg.sender, _token, _quantity);
    }

    /*/////////////////////////
            internal
    /////////////////////////*/

    /// @notice Updates the value of an account balance in the native token decimals.
    /// @param _token The address of the token (address(0) for ETH).
    /// @param _quantity The amount to add or subtract.
    /// @param _operation The type of operation (Extract or Deposit).
    function _updateAccountBalance(
        address _token,
        uint256 _quantity,
        Operation _operation
    ) private {
        // Load and modify the state variable in memory first
        uint256 newBalance;
        uint256 currentBalance = s_accounts[msg.sender][_token];

        if (_operation == Operation.Extract) {
            newBalance = currentBalance - _quantity;
        } else {
            newBalance = currentBalance + _quantity;
        }

        // Write back to storage ONCE
        s_accounts[msg.sender][_token] = newBalance;

        emit KipuBank_SuccessfulBalanceUpdate(msg.sender, _token, newBalance);
    }

    /// @notice Gets the USD value of an amount of a specific asset.
    /// @param _token The asset address (address(0) for ETH).
    /// @param _amount The amount of the asset (in its native decimals).
    /// @return The USD value of the amount, scaled to USD_STANDARD_DECIMALS.
    function _getUSDValue(
        address _token,
        uint256 _amount
    ) private view returns (uint256) {
        if (_amount == 0) return 0;

        // For this simplified example, we'll assume all tokens are ETH or priced against ETH.

        uint256 assetDecimals;
        int256 ethPrice;
        uint8 priceFeedDecimals;

        if (_token == address(0)) {
            // Native ETH deposit
            assetDecimals = 18; // ETH has 18 decimals

            // Get ETH/USD price from Chainlink Oracle
            (, ethPrice, , , ) = i_priceFeed.latestRoundData();
            priceFeedDecimals = i_priceFeed.decimals();

            // Scale ETH amount to USD_STANDARD_DECIMALS
            uint256 rawUSDValue = uint256(ethPrice) * _amount;

            return
                (rawUSDValue * (10 ** USD_STANDARD_DECIMALS)) /
                (10 ** (assetDecimals + priceFeedDecimals));
        } else {
            // ERC-20 token - assumes 18 decimals and 1:1 Peg to USD for simplicity in this exercise
            // NOTE: This is a major assumption and should be fixed in a real contract.
            assetDecimals = 18; // Common ERC20 decimals (e.g., WETH, most tokens)

            // Since we don't have a direct token/USD oracle, we treat it as 1:1 if it has 6 decimals (USDC)
            // If the token has 18 decimals, we scale it back to 6.

            // Standard approach for fixed-price assets like USDC (6 decimals):
            if (assetDecimals > USD_STANDARD_DECIMALS) {
                // Scale down (e.g., 18 to 6)
                return
                    _amount / (10 ** (assetDecimals - USD_STANDARD_DECIMALS));
            } else if (assetDecimals < USD_STANDARD_DECIMALS) {
                // Scale up (e.g., 4 to 6)
                return
                    _amount * (10 ** (USD_STANDARD_DECIMALS - assetDecimals));
            } else {
                return _amount;
            }
        }
    }

    /*/////////////////////////
        View & Pure
    /////////////////////////*/
    /// @notice Get the balance of an account for a specific asset.
    /// @param _token The address of the asset (address(0) for ETH).
    /// @return balance The balance of the sender's account (in token decimals).
    function getBalance(
        address _token
    ) external view returns (uint256 balance) {
        balance = s_accounts[msg.sender][_token];
    }
}
