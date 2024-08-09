// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../data/Ownable2Step.sol";
import "../../data/ReentrancyGuard.sol";
import "../../data/IERC20.sol";
import "../../data/SafeERC20.sol";
import "./IBlast.sol";
import "./IDeferLiquidityCheck.sol";
import "./IAlienFinance.sol";
import "./IPToken.sol";
import "./IWeth.sol";
import "./IWstEth.sol";

contract TxBuilderExtension is ReentrancyGuard, Ownable2Step, IDeferLiquidityCheck {
    using SafeERC20 for IERC20;

    /// @notice The address of Blast
    address public constant BLAST = 0x4300000000000000000000000000000000000002;

    /// @notice The action for deferring liquidity check
    bytes32 public constant ACTION_DEFER_LIQUIDITY_CHECK = "ACTION_DEFER_LIQUIDITY_CHECK";

    /// @notice The action for supplying asset
    bytes32 public constant ACTION_SUPPLY = "ACTION_SUPPLY";

    /// @notice The action for borrowing asset
    bytes32 public constant ACTION_BORROW = "ACTION_BORROW";

    /// @notice The action for redeeming asset
    bytes32 public constant ACTION_REDEEM = "ACTION_REDEEM";

    /// @notice The action for repaying asset
    bytes32 public constant ACTION_REPAY = "ACTION_REPAY";

    /// @notice The action for supplying native token
    bytes32 public constant ACTION_SUPPLY_NATIVE_TOKEN = "ACTION_SUPPLY_NATIVE_TOKEN";

    /// @notice The action for borrowing native token
    bytes32 public constant ACTION_BORROW_NATIVE_TOKEN = "ACTION_BORROW_NATIVE_TOKEN";

    /// @notice The action for redeeming native token
    bytes32 public constant ACTION_REDEEM_NATIVE_TOKEN = "ACTION_REDEEM_NATIVE_TOKEN";

    /// @notice The action for repaying native token
    bytes32 public constant ACTION_REPAY_NATIVE_TOKEN = "ACTION_REPAY_NATIVE_TOKEN";

    /// @notice The action for supplying stEth
    bytes32 public constant ACTION_SUPPLY_STETH = "ACTION_SUPPLY_STETH";

    /// @notice The action for borrowing stEth
    bytes32 public constant ACTION_BORROW_STETH = "ACTION_BORROW_STETH";

    /// @notice The action for redeeming stEth
    bytes32 public constant ACTION_REDEEM_STETH = "ACTION_REDEEM_STETH";

    /// @notice The action for repaying stEth
    bytes32 public constant ACTION_REPAY_STETH = "ACTION_REPAY_STETH";

    /// @notice The action for supplying pToken
    bytes32 public constant ACTION_SUPPLY_PTOKEN = "ACTION_SUPPLY_PTOKEN";

    /// @notice The action for redeeming pToken
    bytes32 public constant ACTION_REDEEM_PTOKEN = "ACTION_REDEEM_PTOKEN";

    /// @dev Transient storage variable used for native token amount
    uint256 private unusedNativeToken;

    /// @notice The address of AlienFinance
    IAlienFinance public immutable alien;

    /// @notice The address of WETH
    address public immutable weth;

    /**
     * @notice Construct a new TxBuilderExtension contract
     * @param alien_ The AlienFinance contract
     * @param weth_ The WETH contract
     * @param gasStation_ The gas station contract
     */
    constructor(address alien_, address weth_, address gasStation_) {
        alien = IAlienFinance(alien_);
        weth = weth_;

        // Blast mainnet
        if (block.chainid == 81457) {
            // Configure gas mode to claimable.
            IBlast(BLAST).configureClaimableGas();
            IBlast(BLAST).configureGovernor(gasStation_);
        }
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    struct Action {
        bytes32 name;
        bytes data;
    }

    /**
     * @notice Execute a list of actions in order
     * @param actions The list of actions
     */
    function execute(Action[] calldata actions) external payable {
        unusedNativeToken = msg.value;

        executeInternal(msg.sender, actions, 0);
    }

    /// @inheritdoc IDeferLiquidityCheck
    function onDeferredLiquidityCheck(bytes memory encodedData) external override {
        require(msg.sender == address(alien), "untrusted message sender");

        (address initiator, Action[] memory actions, uint256 index) =
            abi.decode(encodedData, (address, Action[], uint256));
        executeInternal(initiator, actions, index);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice Admin seizes the asset from the contract.
     * @param recipient The recipient of the seized asset.
     * @param asset The asset to seize.
     */
    function seize(address recipient, address asset) external onlyOwner {
        IERC20(asset).safeTransfer(recipient, IERC20(asset).balanceOf(address(this)));
    }

    /**
     * @notice Admin seizes the native token from the contract.
     * @param recipient The recipient of the seized native token.
     */
    function seizeNative(address recipient) external onlyOwner {
        (bool sent,) = recipient.call{value: address(this).balance}("");
        require(sent, "failed to send native token");
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Execute a list of actions for user in order.
     * @param user The address of the user
     * @param actions The list of actions
     * @param index The index of the action to start with
     */
    function executeInternal(address user, Action[] memory actions, uint256 index) internal {
        uint256 i = index;
        while (i < actions.length) {
            Action memory action = actions[i];
            if (action.name == ACTION_DEFER_LIQUIDITY_CHECK) {
                deferLiquidityCheck(user, abi.encode(user, actions, i + 1));

                // Break the loop as we will re-enter the loop after the liquidity check is deferred.
                break;
            } else if (action.name == ACTION_SUPPLY) {
                (address asset, uint256 amount) = abi.decode(action.data, (address, uint256));
                supply(user, asset, amount);
            } else if (action.name == ACTION_BORROW) {
                (address asset, uint256 amount) = abi.decode(action.data, (address, uint256));
                borrow(user, asset, amount);
            } else if (action.name == ACTION_REDEEM) {
                (address asset, uint256 amount) = abi.decode(action.data, (address, uint256));
                redeem(user, asset, amount);
            } else if (action.name == ACTION_REPAY) {
                (address asset, uint256 amount) = abi.decode(action.data, (address, uint256));
                repay(user, asset, amount);
            } else if (action.name == ACTION_SUPPLY_NATIVE_TOKEN) {
                uint256 supplyAmount = abi.decode(action.data, (uint256));
                supplyNativeToken(user, supplyAmount);
                unusedNativeToken -= supplyAmount;
            } else if (action.name == ACTION_BORROW_NATIVE_TOKEN) {
                uint256 borrowAmount = abi.decode(action.data, (uint256));
                borrowNativeToken(user, borrowAmount);
            } else if (action.name == ACTION_REDEEM_NATIVE_TOKEN) {
                uint256 redeemAmount = abi.decode(action.data, (uint256));
                redeemNativeToken(user, redeemAmount);
            } else if (action.name == ACTION_REPAY_NATIVE_TOKEN) {
                uint256 repayAmount = abi.decode(action.data, (uint256));
                repayAmount = repayNativeToken(user, repayAmount);
                unusedNativeToken -= repayAmount;
            } else if (action.name == ACTION_SUPPLY_PTOKEN) {
                (address pToken, uint256 amount) = abi.decode(action.data, (address, uint256));
                supplyPToken(user, pToken, amount);
            } else if (action.name == ACTION_REDEEM_PTOKEN) {
                (address pToken, uint256 amount) = abi.decode(action.data, (address, uint256));
                redeemPToken(user, pToken, amount);
            } else {
                revert("invalid action");
            }

            unchecked {
                i++;
            }
        }

        // Refund unused native token back to user if the action list is fully executed.
        if (i == actions.length && unusedNativeToken > 0) {
            (bool sent,) = user.call{value: unusedNativeToken}("");
            require(sent, "failed to send native token");
            unusedNativeToken = 0;
        }
    }

    /**
     * @dev Defers the liquidity check.
     * @param user The address of the user
     * @param data The encoded data
     */
    function deferLiquidityCheck(address user, bytes memory data) internal {
        alien.deferLiquidityCheck(user, data);
    }

    /**
     * @dev Supplies the asset to Alien.
     * @param user The address of the user
     * @param asset The address of the asset to supply
     * @param amount The amount of the asset to supply
     */
    function supply(address user, address asset, uint256 amount) internal nonReentrant {
        alien.supply(user, user, asset, amount);
    }

    /**
     * @dev Borrows the asset from Alien.
     * @param user The address of the user
     * @param asset The address of the asset to borrow
     * @param amount The amount of the asset to borrow
     */
    function borrow(address user, address asset, uint256 amount) internal nonReentrant {
        alien.borrow(user, user, asset, amount);
    }

    /**
     * @dev Redeems the asset to Alien.
     * @param user The address of the user
     * @param asset The address of the asset to redeem
     * @param amount The amount of the asset to redeem
     */
    function redeem(address user, address asset, uint256 amount) internal nonReentrant {
        alien.redeem(user, user, asset, amount);
    }

    /**
     * @dev Repays the asset to Alien.
     * @param user The address of the user
     * @param asset The address of the asset to repay
     * @param amount The amount of the asset to repay
     */
    function repay(address user, address asset, uint256 amount) internal nonReentrant {
        alien.repay(user, user, asset, amount);
    }

    /**
     * @dev Wraps the native token and supplies it to Alien.
     * @param user The address of the user
     * @param supplyAmount The amount of the wrapped native token to supply
     */
    function supplyNativeToken(address user, uint256 supplyAmount) internal nonReentrant {
        IWeth(weth).deposit{value: supplyAmount}();
        IERC20(weth).safeIncreaseAllowance(address(alien), supplyAmount);
        alien.supply(address(this), user, weth, supplyAmount);
    }

    /**
     * @dev Borrows the wrapped native token and unwraps it to the user.
     * @param user The address of the user
     * @param borrowAmount The amount of the wrapped native token to borrow
     */
    function borrowNativeToken(address user, uint256 borrowAmount) internal nonReentrant {
        alien.borrow(user, address(this), weth, borrowAmount);
        IWeth(weth).withdraw(borrowAmount);
        (bool sent,) = user.call{value: borrowAmount}("");
        require(sent, "failed to send native token");
    }

    /**
     * @dev Redeems the wrapped native token and unwraps it to the user.
     * @param user The address of the user
     * @param redeemAmount The amount of the wrapped native token to redeem, -1 means redeem all
     */
    function redeemNativeToken(address user, uint256 redeemAmount) internal nonReentrant {
        if (redeemAmount == type(uint256).max) {
            alien.accrueInterest(weth);
            redeemAmount = alien.getSupplyBalance(user, weth);
        }
        alien.redeem(user, address(this), weth, redeemAmount);
        IWeth(weth).withdraw(redeemAmount);
        (bool sent,) = user.call{value: redeemAmount}("");
        require(sent, "failed to send native token");
    }

    /**
     * @dev Wraps the native token and repays it to Alien.
     * @param user The address of the user
     * @param repayAmount The amount of the wrapped native token to repay, -1 means repay all
     */
    function repayNativeToken(address user, uint256 repayAmount) internal nonReentrant returns (uint256) {
        if (repayAmount == type(uint256).max) {
            alien.accrueInterest(weth);
            repayAmount = alien.getBorrowBalance(user, weth);
        }
        IWeth(weth).deposit{value: repayAmount}();
        IERC20(weth).safeIncreaseAllowance(address(alien), repayAmount);
        alien.repay(address(this), user, weth, repayAmount);
        return repayAmount;
    }

    /**
     * @dev Wraps the underlying and supplies the pToken to Alien.
     * @param user The address of the user
     * @param pToken The address of the pToken
     * @param amount The amount of the pToken to supply
     */
    function supplyPToken(address user, address pToken, uint256 amount) internal nonReentrant {
        address underlying = IPToken(pToken).getUnderlying();
        IERC20(underlying).safeTransferFrom(user, pToken, amount);
        IPToken(pToken).absorb(address(this));
        IERC20(pToken).safeIncreaseAllowance(address(alien), amount);
        alien.supply(address(this), user, pToken, amount);
    }

    /**
     * @dev Redeems the pToken and unwraps the underlying to the user.
     * @param user The address of the user
     * @param pToken The address of the pToken
     * @param amount The amount of the pToken to redeem
     */
    function redeemPToken(address user, address pToken, uint256 amount) internal nonReentrant {
        if (amount == type(uint256).max) {
            alien.accrueInterest(pToken);
            amount = alien.getSupplyBalance(user, pToken);
        }
        alien.redeem(user, address(this), pToken, amount);
        IPToken(pToken).unwrap(amount);
        address underlying = IPToken(pToken).getUnderlying();
        IERC20(underlying).safeTransfer(user, amount);
    }

    receive() external payable {}
}
