// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../data/Ownable.sol";
import "../../data/IERC20.sol";
import "../../data/SafeERC20.sol";
import "./IERC3156FlashLender.sol";
import "./IDeferLiquidityCheck.sol";
import "./IAlienFinance.sol";
import "../../data/PauseFlags.sol";

contract FlashLoan is Ownable, IERC3156FlashLender, IDeferLiquidityCheck {
    using SafeERC20 for IERC20;
    using PauseFlags for DataTypes.MarketConfig;

    /// @notice The standard signature for ERC-3156 borrower
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /// @notice The maximum flash loan fee rate
    uint16 internal constant MAX_FEE_RATE = 1000; // 10%

    /// @notice The Alien contract
    address public immutable alien;

    /// @notice The flash loan fee rate
    uint16 public feeRate;

    /// @dev The deferred liquidity check flag
    bool internal _isDeferredLiquidityCheck;

    event FeeRateSet(uint16 feeRate);

    event TokenSeized(address token, uint256 amount);

    constructor(address alien_) {
        alien = alien_;
    }

    /// @inheritdoc IERC3156FlashLender
    function maxFlashLoan(address token) external view override returns (uint256) {
        if (!IAlienFinance(alien).isMarketListed(token)) {
            return 0;
        }

        DataTypes.MarketConfig memory config = IAlienFinance(alien).getMarketConfiguration(token);
        if (config.isBorrowPaused()) {
            return 0;
        }

        uint256 totalCash = IAlienFinance(alien).getTotalCash(token);
        uint256 totalBorrow = IAlienFinance(alien).getTotalBorrow(token);

        uint256 maxBorrowAmount;
        if (config.borrowCap == 0) {
            maxBorrowAmount = totalCash;
        } else if (config.borrowCap > totalBorrow) {
            uint256 gap = config.borrowCap - totalBorrow;
            maxBorrowAmount = gap < totalCash ? gap : totalCash;
        }

        return maxBorrowAmount;
    }

    /// @inheritdoc IERC3156FlashLender
    function flashFee(address token, uint256 amount) external view override returns (uint256) {
        amount;

        require(IAlienFinance(alien).isMarketListed(token), "token not listed");

        DataTypes.MarketConfig memory config = IAlienFinance(alien).getMarketConfiguration(token);
        require(!config.isBorrowPaused(), "borrow is paused");

        return _flashFee(amount);
    }

    /// @inheritdoc IERC3156FlashLender
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data)
        external
        override
        returns (bool)
    {
        require(IAlienFinance(alien).isMarketListed(token), "token not listed");

        if (!_isDeferredLiquidityCheck) {
            IAlienFinance(alien).deferLiquidityCheck(
                address(this), abi.encode(receiver, token, amount, data, msg.sender)
            );
            _isDeferredLiquidityCheck = false;
        } else {
            _loan(receiver, token, amount, data, msg.sender);
        }

        return true;
    }

    /// @inheritdoc IDeferLiquidityCheck
    function onDeferredLiquidityCheck(bytes memory encodedData) external override {
        require(msg.sender == alien, "untrusted message sender");
        (IERC3156FlashBorrower receiver, address token, uint256 amount, bytes memory data, address msgSender) =
            abi.decode(encodedData, (IERC3156FlashBorrower, address, uint256, bytes, address));

        _isDeferredLiquidityCheck = true;
        _loan(receiver, token, amount, data, msgSender);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice Set the flash loan fee rate.
     * @param _feeRate The fee rate
     */
    function setFeeRate(uint16 _feeRate) external onlyOwner {
        require(_feeRate <= MAX_FEE_RATE, "invalid fee rate");

        feeRate = _feeRate;
        emit FeeRateSet(_feeRate);
    }

    /**
     * @notice Seize the token from the contract.
     * @param token The address of the token
     * @param amount The amount to seize
     * @param recipient The address of the recipient
     */
    function seize(address token, uint256 amount, address recipient) external onlyOwner {
        IERC20(token).safeTransfer(recipient, amount);
        emit TokenSeized(token, amount);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Get the flash loan fee.
     * @param amount The amount to flash loan
     */
    function _flashFee(uint256 amount) internal view returns (uint256) {
        return amount * feeRate / 10000;
    }

    /**
     * @dev Flash borrow from Alien to the receiver.
     * @param receiver The receiver of the flash loan
     * @param token The token to borrow
     * @param amount The amount to borrow
     * @param data Arbitrary data that is passed to the receiver
     * @param msgSender The original caller
     */
    function _loan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes memory data, address msgSender)
        internal
    {
        uint256 fee = _flashFee(amount);

        IAlienFinance(alien).borrow(address(this), address(receiver), token, amount);

        require(receiver.onFlashLoan(msgSender, token, amount, fee, data) == CALLBACK_SUCCESS, "callback failed");

        // Collect repayment from the receiver with fee.
        IERC20(token).safeTransferFrom(address(receiver), address(this), amount + fee);

        uint256 allowance = IERC20(token).allowance(address(this), alien);
        if (allowance < amount) {
            IERC20(token).safeApprove(alien, type(uint256).max);
        }

        // Only repay the principal amount to Alien.
        IAlienFinance(alien).repay(address(this), address(this), token, amount);
    }
}
