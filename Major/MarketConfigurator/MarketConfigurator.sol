// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../data/Ownable2Step.sol";
import "../../data/IERC20Metadata.sol";
import "./Constants.sol";
import "../../interfaces/IAlienFinance.sol";
import "../../interfaces/IAToken.sol";
import "../../interfaces/IDebtToken.sol";
import "../../data/IPToken.sol";
import "../../data/DataTypes.sol";
import "../../data/PauseFlags.sol";

contract MarketConfigurator is Ownable2Step, Constants {
    using PauseFlags for DataTypes.MarketConfig;

    /// @notice The Alien contract
    IAlienFinance public immutable alien;

    /// @notice The address of the guardian
    address public guardian;

    event GuardianSet(address guardian);
    event MarketListed(
        address market,
        address aToken,
        address debtToken,
        address interestRateModel,
        uint16 reserveFactor,
        bool isPToken
    );
    event MarketDelisted(address market);
    event MarketCollateralFactorSet(address market, uint16 collateralFactor);
    event MarketLiquidationThresholdSet(address market, uint16 liquidationThreshold);
    event MarketLiquidationBonusSet(address market, uint16 liquidationBonus);
    event MarketReserveFactorSet(address market, uint16 reserveFactor);
    event MarketInterestRateModelSet(address market, address interestRateModel);
    event MarketSupplyCapSet(address market, uint256 cap);
    event MarketBorrowCapSet(address market, uint256 cap);
    event MarketPausedSet(address market, string action, bool paused);
    event MarketFrozen(address market, bool state);
    event MarketConfiguredAsPToken(address market);

    constructor(address alien_) {
        alien = IAlienFinance(alien_);
    }

    /**
     * @notice Check if the caller is the owner or the guardian.
     */
    modifier onlyOwnerOrGuardian() {
        _checkOwnerOrGuardian();
        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Get the market configuration of a market.
     * @return The market configuration
     */
    function getMarketConfiguration(address market) public view returns (DataTypes.MarketConfig memory) {
        return alien.getMarketConfiguration(market);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice Set the guardian of market configurator.
     * @param _guardian The address of the guardian
     */
    function setGuardian(address _guardian) external onlyOwner {
        guardian = _guardian;

        emit GuardianSet(guardian);
    }

    /**
     * @notice List a market to Alien.
     * @dev If the pToken of the market was listed before, need to call `setMarketPToken` to set the pToken address.
     * @param market The market to be listed
     * @param aTokenAddress The address of the aToken
     * @param debtTokenAddress The address of the debtToken
     * @param interestRateModelAddress The address of the interest rate model
     * @param reserveFactor The reserve factor of the market
     */
    function listMarket(
        address market,
        address aTokenAddress,
        address debtTokenAddress,
        address interestRateModelAddress,
        uint16 reserveFactor
    ) external onlyOwner {
        _listMarket(market, aTokenAddress, debtTokenAddress, interestRateModelAddress, reserveFactor, false);
    }

    /**
     * @notice List a pToken market to Alien.
     * @param market The market to be listed
     * @param aTokenAddress The address of the aToken
     * @param interestRateModelAddress The address of the interest rate model
     * @param reserveFactor The reserve factor of the market
     */
    function listPTokenMarket(
        address market,
        address aTokenAddress,
        address interestRateModelAddress,
        uint16 reserveFactor
    ) external onlyOwner {
        _listMarket(market, aTokenAddress, address(0), interestRateModelAddress, reserveFactor, true);
    }

    /**
     * @notice Configure a market as collateral.
     * @dev This function is used for the first time to configure a market as collateral.
     * @param market The market to be configured
     * @param collateralFactor The collateral factor of the market
     * @param liquidationThreshold The liquidation threshold of the market
     * @param liquidationBonus The liquidation bonus of the market
     */
    function configureMarketAsCollateral(
        address market,
        uint16 collateralFactor,
        uint16 liquidationThreshold,
        uint16 liquidationBonus
    ) external onlyOwner {
        DataTypes.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");
        require(
            config.collateralFactor == 0 && config.liquidationThreshold == 0 && config.liquidationBonus == 0,
            "already configured"
        );
        require(collateralFactor > 0 && collateralFactor <= MAX_COLLATERAL_FACTOR, "invalid collateral factor");
        require(
            liquidationThreshold > 0 && liquidationThreshold <= MAX_LIQUIDATION_THRESHOLD
                && liquidationThreshold >= collateralFactor,
            "invalid liquidation threshold"
        );
        require(
            liquidationBonus > MIN_LIQUIDATION_BONUS && liquidationBonus <= MAX_LIQUIDATION_BONUS,
            "invalid liquidation bonus"
        );
        require(
            uint256(liquidationThreshold) * uint256(liquidationBonus) / FACTOR_SCALE
                <= MAX_LIQUIDATION_THRESHOLD_X_BONUS,
            "liquidation threshold * liquidation bonus larger than 100%"
        );

        config.collateralFactor = collateralFactor;
        config.liquidationThreshold = liquidationThreshold;
        config.liquidationBonus = liquidationBonus;
        alien.setMarketConfiguration(market, config);

        emit MarketCollateralFactorSet(market, collateralFactor);
        emit MarketLiquidationThresholdSet(market, liquidationThreshold);
        emit MarketLiquidationBonusSet(market, liquidationBonus);
    }

    /**
     * @notice Adjust the collateral factor of a market.
     * @param market The market to be adjusted
     * @param collateralFactor The new collateral factor of the market
     */
    function adjustMarketCollateralFactor(address market, uint16 collateralFactor) external onlyOwner {
        DataTypes.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");
        if (collateralFactor > 0) {
            require(collateralFactor <= MAX_COLLATERAL_FACTOR, "invalid collateral factor");
            require(
                collateralFactor <= config.liquidationThreshold, "collateral factor larger than liquidation threshold"
            );
        }

        config.collateralFactor = collateralFactor;
        alien.setMarketConfiguration(market, config);

        emit MarketCollateralFactorSet(market, collateralFactor);
    }

    /**
     * @notice Adjust the reserve factor of a market.
     * @param market The market to be adjusted
     * @param reserveFactor The new reserve factor of the market
     */
    function adjustMarketReserveFactor(address market, uint16 reserveFactor) external onlyOwner {
        DataTypes.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");
        require(reserveFactor <= MAX_RESERVE_FACTOR, "invalid reserve factor");

        // Accrue interests before changing reserve factor.
        alien.accrueInterest(market);

        config.reserveFactor = reserveFactor;
        alien.setMarketConfiguration(market, config);

        emit MarketReserveFactorSet(market, reserveFactor);
    }

    /**
     * @notice Adjust the liquidation threshold of a market.
     * @param market The market to be adjusted
     * @param liquidationThreshold The new liquidation threshold of the market
     */
    function adjustMarketLiquidationThreshold(address market, uint16 liquidationThreshold) external onlyOwner {
        DataTypes.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");
        if (liquidationThreshold > 0) {
            require(liquidationThreshold <= MAX_LIQUIDATION_THRESHOLD, "invalid liquidation threshold");
            require(
                liquidationThreshold >= config.collateralFactor, "liquidation threshold smaller than collateral factor"
            );
            require(
                uint256(liquidationThreshold) * uint256(config.liquidationBonus) / FACTOR_SCALE
                    <= MAX_LIQUIDATION_THRESHOLD_X_BONUS,
                "liquidation threshold * liquidation bonus larger than 100%"
            );
        } else {
            require(config.collateralFactor == 0, "collateral factor not zero");
        }

        config.liquidationThreshold = liquidationThreshold;
        alien.setMarketConfiguration(market, config);

        emit MarketLiquidationThresholdSet(market, liquidationThreshold);
    }

    /**
     * @notice Adjust the liquidation bonus of a market.
     * @param market The market to be adjusted
     * @param liquidationBonus The new liquidation bonus of the market
     */
    function adjustMarketLiquidationBonus(address market, uint16 liquidationBonus) external onlyOwner {
        DataTypes.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");
        if (liquidationBonus > 0) {
            require(
                liquidationBonus > MIN_LIQUIDATION_BONUS && liquidationBonus <= MAX_LIQUIDATION_BONUS,
                "invalid liquidation bonus"
            );
            require(
                uint256(config.liquidationThreshold) * uint256(liquidationBonus) / FACTOR_SCALE
                    <= MAX_LIQUIDATION_THRESHOLD_X_BONUS,
                "liquidation threshold * liquidation bonus larger than 100%"
            );
        } else {
            require(
                config.collateralFactor == 0 && config.liquidationThreshold == 0,
                "collateral factor or liquidation threshold not zero"
            );
        }

        config.liquidationBonus = liquidationBonus;
        alien.setMarketConfiguration(market, config);

        emit MarketLiquidationBonusSet(market, liquidationBonus);
    }

    /**
     * @notice Change the interest rate model of a market.
     * @param market The market to be changed
     * @param interestRateModelAddress The new interest rate model of the market
     */
    function changeMarketInterestRateModel(address market, address interestRateModelAddress) external onlyOwner {
        DataTypes.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");

        // Accrue interests before changing IRM.
        alien.accrueInterest(market);

        config.interestRateModelAddress = interestRateModelAddress;
        alien.setMarketConfiguration(market, config);

        emit MarketInterestRateModelSet(market, interestRateModelAddress);
    }

    /**
     * @notice Soft delist a market.
     * @dev Soft delisting a market means that the supply and borrow will be paused and the reserve factor will be set to 100%.
     * @param market The market to be soft delisted
     */
    function softDelistMarket(address market) external onlyOwner {
        DataTypes.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");

        if (!config.isSupplyPaused()) {
            config.setSupplyPaused(true);
            emit MarketPausedSet(market, "supply", true);
        }
        if (!config.isBorrowPaused()) {
            config.setBorrowPaused(true);
            emit MarketPausedSet(market, "borrow", true);
        }
        if (config.reserveFactor != MAX_RESERVE_FACTOR) {
            // Accrue interests before changing reserve factor.
            alien.accrueInterest(market);

            config.reserveFactor = MAX_RESERVE_FACTOR;
            emit MarketReserveFactorSet(market, MAX_RESERVE_FACTOR);
        }
        alien.setMarketConfiguration(market, config);
    }

    /**
     * @notice Hard delist a market.
     * @param market The market to be hard delisted
     */
    function hardDelistMarket(address market) external onlyOwner {
        DataTypes.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");
        require(config.isSupplyPaused() && config.isBorrowPaused(), "not paused");
        require(config.reserveFactor == MAX_RESERVE_FACTOR, "reserve factor not max");
        require(
            config.collateralFactor == 0 && config.liquidationThreshold == 0,
            "collateral factor or liquidation threshold not zero"
        );

        alien.delistMarket(market);

        emit MarketDelisted(market);
    }

    /**
     * @notice Pause or unpause the transfer of a market's aToken.
     * @param market The market's aToken to be paused or unpaused
     * @param paused Pause or unpause
     */
    function setMarketTransferPaused(address market, bool paused) external onlyOwner {
        DataTypes.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");

        config.setTransferPaused(paused);
        alien.setMarketConfiguration(market, config);

        emit MarketPausedSet(market, "transfer", paused);
    }

    struct MarketCap {
        address market;
        uint256 cap;
    }

    /**
     * @notice Set the supply cap of a list of markets.
     * @param marketCaps The list of markets and their supply caps
     */
    function setMarketSupplyCaps(MarketCap[] calldata marketCaps) external onlyOwnerOrGuardian {
        uint256 length = marketCaps.length;
        for (uint256 i = 0; i < length;) {
            address market = marketCaps[i].market;
            uint256 cap = marketCaps[i].cap;
            DataTypes.MarketConfig memory config = getMarketConfiguration(market);
            require(config.isListed, "not listed");

            config.supplyCap = cap;
            alien.setMarketConfiguration(market, config);

            emit MarketSupplyCapSet(market, cap);

            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice Set the borrow cap of a list of markets.
     * @param marketCaps The list of markets and their borrow caps
     */
    function setMarketBorrowCaps(MarketCap[] calldata marketCaps) external onlyOwnerOrGuardian {
        uint256 length = marketCaps.length;
        for (uint256 i = 0; i < length;) {
            address market = marketCaps[i].market;
            uint256 cap = marketCaps[i].cap;
            DataTypes.MarketConfig memory config = getMarketConfiguration(market);
            require(config.isListed, "not listed");
            require(!config.isPToken, "cannot set borrow cap for pToken");

            config.borrowCap = cap;
            alien.setMarketConfiguration(market, config);

            emit MarketBorrowCapSet(market, cap);

            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice Pause or unpause the supply of a market.
     * @param market The market to be paused or unpaused
     * @param paused Pause or unpause
     */
    function setMarketSupplyPaused(address market, bool paused) external onlyOwnerOrGuardian {
        DataTypes.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");

        config.setSupplyPaused(paused);
        alien.setMarketConfiguration(market, config);

        emit MarketPausedSet(market, "supply", paused);
    }

    /**
     * @notice Pause or unpause the borrow of a market.
     * @param market The market to be paused or unpaused
     * @param paused Pause or unpause
     */
    function setMarketBorrowPaused(address market, bool paused) external onlyOwnerOrGuardian {
        DataTypes.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");
        require(!config.isPToken, "cannot set borrow paused for pToken");

        config.setBorrowPaused(paused);
        alien.setMarketConfiguration(market, config);

        emit MarketPausedSet(market, "borrow", paused);
    }

    /**
     * @notice Configure a market as a pToken.
     * @dev This function can be called when the pToken was accidentally listed by using `listMarket` function.
     * @param market The market to be configured as a pToken
     */
    function configureMarketAsPToken(address market) external onlyOwnerOrGuardian {
        // Simple sanity check to make sure the market is a pToken.
        IPToken(market).getUnderlying();

        DataTypes.MarketConfig memory config = getMarketConfiguration(market);
        require(config.isListed, "not listed");
        require(!config.isPToken, "already a pToken");

        config.isPToken = true;
        config.setBorrowPaused(true);
        // Set the borrow cap to a very small amount (1 Wei) to prevent borrowing.
        config.borrowCap = 1;

        alien.setMarketConfiguration(market, config);

        emit MarketConfiguredAsPToken(market);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Check if the caller is the owner or guardian.
     */
    function _checkOwnerOrGuardian() internal view {
        require(msg.sender == owner() || msg.sender == guardian, "!authorized");
    }

    /**
     * @dev List a vanilla market or a pToken market. Markets that were delisted can't be listed again.
     * @param market The market to be listed
     * @param aTokenAddress The aToken of the market
     * @param debtTokenAddress The debtToken of the market
     * @param interestRateModelAddress The interest rate model of the market
     * @param reserveFactor The reserve factor of the market
     * @param isPToken Whether the market is a pToken market
     */
    function _listMarket(
        address market,
        address aTokenAddress,
        address debtTokenAddress,
        address interestRateModelAddress,
        uint16 reserveFactor,
        bool isPToken
    ) internal {
        DataTypes.MarketConfig memory config = getMarketConfiguration(market);
        require(!config.isListed, "already listed");
        require(!config.isDelisted, "already delisted");
        require(IAToken(aTokenAddress).asset() == market, "mismatch market");
        if (!isPToken) {
            require(IDebtToken(debtTokenAddress).asset() == market, "mismatch market");
        }
        require(reserveFactor <= MAX_RESERVE_FACTOR, "invalid reserve factor");

        uint8 underlyingDecimals = IERC20Metadata(market).decimals();
        require(underlyingDecimals <= 18, "nonstandard token decimals");

        config.isListed = true;
        config.aTokenAddress = aTokenAddress;
        config.interestRateModelAddress = interestRateModelAddress;
        config.reserveFactor = reserveFactor;
        config.initialExchangeRate = 10 ** underlyingDecimals;
        if (isPToken) {
            config.isPToken = true;
            config.setBorrowPaused(true);
            // Set the borrow cap to a very small amount (1 Wei) to prevent borrowing.
            config.borrowCap = 1;
        } else {
            config.debtTokenAddress = debtTokenAddress;
        }

        alien.listMarket(market, config);

        emit MarketListed(market, aTokenAddress, debtTokenAddress, interestRateModelAddress, reserveFactor, isPToken);
    }
}
