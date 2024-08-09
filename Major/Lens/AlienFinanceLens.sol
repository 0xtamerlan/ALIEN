// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../data/IERC20.sol";
import "../../data/IERC20Metadata.sol";
import "../../interfaces/IInterestRateModel.sol";
import "../../interfaces/IPriceOracle.sol";
import "../../data/IPToken.sol";
import "../../data/DataTypes.sol";
import "../../data/PauseFlags.sol";
import "./AlienFinance.sol";
import "./Constants.sol";

contract AlienFinanceLens is Constants {
    using PauseFlags for DataTypes.MarketConfig;

    struct MarketMetadata {
        address market;
        string marketName;
        string marketSymbol;
        uint8 marketDecimals;
        bool isListed;
        uint16 collateralFactor;
        uint16 liquidationThreshold;
        uint16 liquidationBonus;
        uint16 reserveFactor;
        bool isPToken;
        bool supplyPaused;
        bool borrowPaused;
        bool transferPaused;
        bool isSoftDelisted;
        address aTokenAddress;
        address debtTokenAddress;
        address interestRateModelAddress;
        uint256 supplyCap;
        uint256 borrowCap;
    }

    struct MarketStatus {
        address market;
        uint256 totalCash;
        uint256 totalBorrow;
        uint256 totalSupply;
        uint256 totalReserves;
        uint256 maxSupplyAmount;
        uint256 maxBorrowAmount;
        uint256 marketPrice;
        uint256 exchangeRate;
        uint256 supplyRate;
        uint256 borrowRate;
    }

    struct UserMarketStatus {
        address market;
        uint256 balance;
        uint256 allowanceToAlien;
        uint256 exchangeRate;
        uint256 aTokenBalance;
        uint256 supplyBalance;
        uint256 borrowBalance;
    }

    /**
     * @notice Gets the market metadata for a given market.
     * @param alien The Alien contract
     * @param market The market to get metadata for
     * @return The market metadata
     */
    function getMarketMetadata(AlienFinance alien, address market) public view returns (MarketMetadata memory) {
        return _getMarketMetadata(alien, market);
    }

    /**
     * @notice Gets the market metadata for all markets.
     * @param alien The Alien contract
     * @return The list of all market metadata
     */
    function getAllMarketsMetadata(AlienFinance alien) public view returns (MarketMetadata[] memory) {
        address[] memory markets = alien.getAllMarkets();
        MarketMetadata[] memory configs = new MarketMetadata[](markets.length);
        for (uint256 i = 0; i < markets.length; i++) {
            configs[i] = _getMarketMetadata(alien, markets[i]);
        }
        return configs;
    }

    /**
     * @notice Gets the market status for a given market.
     * @param alien The Alien contract
     * @param market The market to get status for
     * @return The market status
     */
    function getMarketStatus(AlienFinance alien, address market) public view returns (MarketStatus memory) {
        IPriceOracle oracle = IPriceOracle(alien.priceOracle());
        return _getMarketStatus(alien, market, oracle);
    }

    /**
     * @notice Gets the current market status for a given market.
     * @dev This function is not gas efficient and should _not_ be called on chain.
     * @param alien The Alien contract
     * @param market The market to get status for
     * @return The market status
     */
    function getCurrentMarketStatus(AlienFinance alien, address market) public returns (MarketStatus memory) {
        IPriceOracle oracle = IPriceOracle(alien.priceOracle());
        alien.accrueInterest(market);
        return _getMarketStatus(alien, market, oracle);
    }

    /**
     * @notice Gets the market status for all markets.
     * @param alien The Alien contract
     * @return The list of all market status
     */
    function getAllMarketsStatus(AlienFinance alien) public view returns (MarketStatus[] memory) {
        address[] memory allMarkets = alien.getAllMarkets();
        uint256 length = allMarkets.length;

        IPriceOracle oracle = IPriceOracle(alien.priceOracle());

        MarketStatus[] memory marketStatus = new MarketStatus[](length);
        for (uint256 i = 0; i < length; i++) {
            marketStatus[i] = _getMarketStatus(alien, allMarkets[i], oracle);
        }
        return marketStatus;
    }

    /**
     * @notice Gets the current market status for all markets.
     * @dev This function is not gas efficient and should _not_ be called on chain.
     * @param alien The Alien contract
     * @return The list of all market status
     */
    function getAllCurrentMarketsStatus(AlienFinance alien) public returns (MarketStatus[] memory) {
        address[] memory allMarkets = alien.getAllMarkets();
        uint256 length = allMarkets.length;

        IPriceOracle oracle = IPriceOracle(alien.priceOracle());

        MarketStatus[] memory marketStatus = new MarketStatus[](length);
        for (uint256 i = 0; i < length; i++) {
            alien.accrueInterest(allMarkets[i]);
            marketStatus[i] = _getMarketStatus(alien, allMarkets[i], oracle);
        }
        return marketStatus;
    }

    /**
     * @notice Gets the user's market status for a given market.
     * @param alien The Alien contract
     * @param user The user to get status for
     * @param market The market to get status for
     * @return The user's market status
     */
    function getUserMarketStatus(AlienFinance alien, address user, address market)
        public
        view
        returns (UserMarketStatus memory)
    {
        return UserMarketStatus({
            market: market,
            balance: IERC20(market).balanceOf(user),
            allowanceToAlien: IERC20(market).allowance(user, address(alien)),
            exchangeRate: alien.getExchangeRate(market),
            aTokenBalance: alien.getATokenBalance(user, market),
            supplyBalance: alien.getSupplyBalance(user, market),
            borrowBalance: alien.getBorrowBalance(user, market)
        });
    }

    /**
     * @notice Gets the user's current market status for a given market.
     * @dev This function is not gas efficient and should _not_ be called on chain.
     * @param alien The Alien contract
     * @param user The user to get status for
     * @param market The market to get status for
     * @return The user's market status
     */
    function getCurrentUserMarketStatus(AlienFinance alien, address user, address market)
        public
        returns (UserMarketStatus memory)
    {
        alien.accrueInterest(market);

        return UserMarketStatus({
            market: market,
            balance: IERC20(market).balanceOf(user),
            allowanceToAlien: IERC20(market).allowance(user, address(alien)),
            exchangeRate: alien.getExchangeRate(market),
            aTokenBalance: alien.getATokenBalance(user, market),
            supplyBalance: alien.getSupplyBalance(user, market),
            borrowBalance: alien.getBorrowBalance(user, market)
        });
    }

    /**
     * @notice Gets the user's market status for all markets.
     * @param alien The Alien contract
     * @param user The user to get status for
     * @return The list of all user's market status
     */
    function getUserAllMarketsStatus(AlienFinance alien, address user)
        public
        view
        returns (UserMarketStatus[] memory)
    {
        address[] memory allMarkets = alien.getAllMarkets();
        uint256 length = allMarkets.length;

        UserMarketStatus[] memory userMarketStatus = new UserMarketStatus[](length);
        for (uint256 i = 0; i < length; i++) {
            userMarketStatus[i] = getUserMarketStatus(alien, user, allMarkets[i]);
        }
        return userMarketStatus;
    }

    /**
     * @notice Gets the user's current market status for all markets.
     * @dev This function is not gas efficient and should _not_ be called on chain.
     * @param alien The Alien contract
     * @param user The user to get status for
     * @return The list of all user's market status
     */
    function getUserAllCurrentMarketsStatus(AlienFinance alien, address user)
        public
        returns (UserMarketStatus[] memory)
    {
        address[] memory allMarkets = alien.getAllMarkets();
        uint256 length = allMarkets.length;

        UserMarketStatus[] memory userMarketStatus = new UserMarketStatus[](length);
        for (uint256 i = 0; i < length; i++) {
            userMarketStatus[i] = getCurrentUserMarketStatus(alien, user, allMarkets[i]);
        }
        return userMarketStatus;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Gets the market metadata for a given market.
     * @param alien The Alien contract
     * @param market The market to get metadata for
     * @return The market metadata
     */
    function _getMarketMetadata(AlienFinance alien, address market) internal view returns (MarketMetadata memory) {
        DataTypes.MarketConfig memory config = alien.getMarketConfiguration(market);
        bool isSoftDelisted =
            config.isSupplyPaused() && config.isBorrowPaused() && config.reserveFactor == MAX_RESERVE_FACTOR;
        return MarketMetadata({
            market: market,
            marketName: IERC20Metadata(market).name(),
            marketSymbol: IERC20Metadata(market).symbol(),
            marketDecimals: IERC20Metadata(market).decimals(),
            isListed: config.isListed,
            collateralFactor: config.collateralFactor,
            liquidationThreshold: config.liquidationThreshold,
            liquidationBonus: config.liquidationBonus,
            reserveFactor: config.reserveFactor,
            isPToken: config.isPToken,
            supplyPaused: config.isSupplyPaused(),
            borrowPaused: config.isBorrowPaused(),
            transferPaused: config.isTransferPaused(),
            isSoftDelisted: isSoftDelisted,
            aTokenAddress: config.aTokenAddress,
            debtTokenAddress: config.debtTokenAddress,
            interestRateModelAddress: config.interestRateModelAddress,
            supplyCap: config.supplyCap,
            borrowCap: config.borrowCap
        });
    }

    /**
     * @dev Gets the market status for a given market.
     * @param alien The Alien contract
     * @param market The market to get status for
     * @param oracle The price oracle contract
     * @return The market status
     */
    function _getMarketStatus(AlienFinance alien, address market, IPriceOracle oracle)
        internal
        view
        returns (MarketStatus memory)
    {
        DataTypes.MarketConfig memory config = alien.getMarketConfiguration(market);
        uint256 totalCash = alien.getTotalCash(market);
        uint256 totalBorrow = alien.getTotalBorrow(market);
        uint256 totalSupply = alien.getTotalSupply(market);
        uint256 totalReserves = alien.getTotalReserves(market);

        IInterestRateModel irm = IInterestRateModel(config.interestRateModelAddress);

        uint256 totalSupplyUnderlying = totalSupply * alien.getExchangeRate(market) / 1e18;
        uint256 maxSupplyAmount;
        if (config.supplyCap == 0) {
            maxSupplyAmount = type(uint256).max;
        } else if (config.supplyCap > totalSupplyUnderlying) {
            maxSupplyAmount = config.supplyCap - totalSupplyUnderlying;
        }

        uint256 maxBorrowAmount;
        if (config.isPToken) {
            maxBorrowAmount = 0;
        } else if (config.borrowCap == 0) {
            maxBorrowAmount = totalCash;
        } else if (config.borrowCap > totalBorrow) {
            uint256 gap = config.borrowCap - totalBorrow;
            maxBorrowAmount = gap < totalCash ? gap : totalCash;
        }

        return MarketStatus({
            market: market,
            totalCash: totalCash,
            totalBorrow: totalBorrow,
            totalSupply: totalSupply,
            totalReserves: totalReserves,
            maxSupplyAmount: maxSupplyAmount,
            maxBorrowAmount: maxBorrowAmount,
            marketPrice: getMarketPrice(config.isPToken, market, oracle),
            exchangeRate: alien.getExchangeRate(market),
            supplyRate: irm.getSupplyRate(totalCash, totalBorrow),
            borrowRate: irm.getBorrowRate(totalCash, totalBorrow)
        });
    }

    /**
     * @dev Get the market price for a given market.
     * @param isPToken Whether the market is a pToken
     * @param market The market to get price for
     * @param oracle The price oracle contract
     * @return The market price
     */
    function getMarketPrice(bool isPToken, address market, IPriceOracle oracle) internal view returns (uint256) {
        if (isPToken) {
            market = IPToken(market).getUnderlying();
        }
        return oracle.getPrice(market);
    }
}
