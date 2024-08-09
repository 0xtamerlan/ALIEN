// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./AggregatorV3Interface.sol";
import "src/data/Ownable.sol";
import "src/data/IERC20Metadata.sol";
import "./IPriceOracle.sol";

contract BlastPriceOracle is Ownable, IPriceOracle {
    /// @notice The min update interval (5 minutes)
    uint256 public constant UPDATE_INTERVAL = 5 minutes;

    /// @notice The max swing of the price per update (20%)
    uint256 public constant MAX_SWING = 2000;

    /// @notice The poster address
    address public poster;

    /// @notice The red stone price feeds
    mapping(address => address) public redStoneFeeds;

    /// @notice The fallback price of the assets
    mapping(address => uint256) public fallbackPrices;

    /// @notice The last updated time of the assets
    mapping(address => uint256) public lastUpdated;

    event PosterSet(address poster);

    event PriceFeedSet(address asset, address priceFeed);

    event FallbackPriceSet(address asset, uint256 price);

    modifier onlyPoster() {
        _checkPoster();
        _;
    }

    /**
     * @notice Gets the price of an asset
     * @param asset The asset to get the price of
     * @return The price of the asset
     */
    function getPrice(address asset) external view returns (uint256) {
        address priceFeed = redStoneFeeds[asset];
        if (priceFeed != address(0)) {
            uint256 price = _getPriceFromRedStone(priceFeed);
            return _getNormalizedPrice(price, asset);
        }

        uint256 fallbackPrice = fallbackPrices[asset];
        require(fallbackPrice > 0, "invalid fallback price");
        return fallbackPrice;
    }

    struct PriceData {
        address asset;
        uint256 price;
    }

    /**
     * @notice Sets the fallback price of the assets
     * @param priceData The price data
     */
    function setFallbackPrices(PriceData[] memory priceData) external onlyPoster {
        for (uint256 i = 0; i < priceData.length;) {
            address asset = priceData[i].asset;
            uint256 price = priceData[i].price;
            require(price > 0, "invalid price");

            // Check the max swing and last update time.
            if (fallbackPrices[asset] != 0) {
                uint256 maxPrice = fallbackPrices[asset] * (MAX_SWING + 10000) / 10000;
                uint256 minPrice = fallbackPrices[asset] * (10000 - MAX_SWING) / 10000;
                require(price <= maxPrice && price >= minPrice, "price swing too high");
                require(block.timestamp - lastUpdated[asset] >= UPDATE_INTERVAL, "min update interval not reached");
            }

            // Update the price and last updated time.
            fallbackPrices[asset] = price;
            lastUpdated[asset] = block.timestamp;

            emit FallbackPriceSet(asset, price);

            unchecked {
                i++;
            }
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice Sets the poster address
     * @param _poster The poster address
     */
    function setPoster(address _poster) external onlyOwner {
        poster = _poster;

        emit PosterSet(_poster);
    }

    struct PriceFeedData {
        address asset;
        address priceFeed;
    }

    /**
     * @notice Sets the red stone price feeds
     * @param priceFeedData The price feed data
     */
    function setRedStonePriceFeeds(PriceFeedData[] memory priceFeedData) external onlyOwner {
        for (uint256 i = 0; i < priceFeedData.length;) {
            address asset = priceFeedData[i].asset;
            address priceFeed = priceFeedData[i].priceFeed;

            if (priceFeed != address(0)) {
                (, int256 price,,,) = AggregatorV3Interface(priceFeed).latestRoundData();
                require(price > 0, "invalid price");
            }

            redStoneFeeds[asset] = priceFeed;

            emit PriceFeedSet(asset, priceFeed);

            unchecked {
                i++;
            }
        }
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev Checks whether the caller is the poster
     */
    function _checkPoster() internal view {
        require(msg.sender == poster, "caller is not the poster");
    }

    /**
     * @dev Gets the price from the red stone price feed
     * @param priceFeed The price feed
     * @return The price
     */
    function _getPriceFromRedStone(address priceFeed) internal view returns (uint256) {
        (, int256 price,,,) = AggregatorV3Interface(priceFeed).latestRoundData();
        require(price > 0, "invalid price");

        // Extend the decimals to 1e18.
        return uint256(price) * 10 ** (18 - uint256(AggregatorV3Interface(priceFeed).decimals()));
    }

    /**
     * @dev Get the normalized price.
     * @param price The price
     * @param asset The asset
     * @return The normalized price
     */
    function _getNormalizedPrice(uint256 price, address asset) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(asset).decimals();
        return price * 10 ** (18 - decimals);
    }
}
