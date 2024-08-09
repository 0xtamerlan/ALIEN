// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
//import {Initializable} from "src/data/Initializable.sol";
//import {UUPSUpgradeable} from "src/data/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ATokenStorage} from "./ATokenStorage.sol";
import {IAToken} from "../../interfaces/IAToken.sol";
import {IAlienFinance} from "../../interfaces/IAlienFinance.sol";

//new
//import "src/data/AddressUpgradeable.sol";

contract AToken is /*Initializable,*/
    ERC20Upgradeable, /*UUPSUpgradeable,*/
    OwnableUpgradeable,
    ATokenStorage,
    IAToken
{
    //     //new
    //     uint8 private _initialized;
    //     bool private _initializing;

    //      modifier initializer() {
    //     bool isTopLevelCall = !_initializing;
    //     require(
    //         (isTopLevelCall && _initialized < 1) || (!AddressUpgradeable.isContract(address(this)) && _initialized == 1),
    //         "Initializable: contract is already initialized"
    //     );
    //     _initialized = 1;
    //     if (isTopLevelCall) {
    //         _initializing = true;
    //     }
    //     _;
    //     if (isTopLevelCall) {
    //         _initializing = false;
    //         emit Initialized(1);
    //     }
    // }
    // //end new

    function initialize(string memory name_, string memory symbol_, address admin_, address alien_, address market_)
        public
        initializer
    {
        __ERC20_init(name_, symbol_);
        __Ownable_init();
        //__UUPSUpgradeable_init();

        transferOwnership(admin_);
        alien = alien_;
        market = market_;
    }

    /**
     * @notice Check if the caller is Alien.
     */
    modifier onlyAlien() {
        _checkAlien();
        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice Return the underlying market.
     */
    function asset() public view returns (address) {
        return market;
    }

    /// @inheritdoc ERC20Upgradeable
    function totalSupply() public view virtual override returns (uint256) {
        return IAlienFinance(alien).getTotalSupply(market);
    }

    /// @inheritdoc ERC20Upgradeable
    function balanceOf(address account) public view override returns (uint256) {
        return IAlienFinance(alien).getATokenBalance(account, market);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Transfer AToken to another address.
     * @param to The address to receive AToken
     * @param amount The amount of AToken to transfer
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        IAlienFinance(alien).transferAToken(market, msg.sender, to, amount);
        return super.transfer(to, amount);
    }

    /**
     * @notice Transfer AToken from one address to another.
     * @param from The address to send AToken from
     * @param to The address to receive AToken
     * @param amount The amount of AToken to transfer
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        IAlienFinance(alien).transferAToken(market, from, to, amount);
        return super.transferFrom(from, to, amount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice Mint AToken.
     * @dev This function will only emit a Transfer event.
     * @param account The address to receive AToken
     * @param amount The amount of AToken to mint
     */
    function mint(address account, uint256 amount) external onlyAlien {
        emit Transfer(address(0), account, amount);
    }

    /**
     * @notice Burn AToken.
     * @dev This function will only emit a Transfer event.
     * @param account The address to burn AToken from
     * @param amount The amount of AToken to burn
     */
    function burn(address account, uint256 amount) external onlyAlien {
        emit Transfer(account, address(0), amount);
    }

    /**
     * @notice Seize AToken.
     * @dev This function will only be called when a liquidation occurs.
     * @param from The address to seize AToken from
     * @param to The address to receive AToken
     * @param amount The amount of AToken to seize
     */
    function seize(address from, address to, uint256 amount) external onlyAlien {
        _transfer(from, to, amount);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @dev _authorizeUpgrade is used by UUPSUpgradeable to determine if it's allowed to upgrade a proxy implementation.
     * @param newImplementation The new implementation
     *
     * Ref: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/proxy/utils/UUPSUpgradeable.sol
     */
    function _authorizeUpgrade(address newImplementation) internal onlyOwner {}

    /**
     * @dev Check if the caller is the Alien.
     */
    function _checkAlien() internal view {
        require(msg.sender == alien, "!authorized");
    }

    /// @inheritdoc ERC20Upgradeable
    function _transfer(address from, address to, uint256 amount) internal override {
        emit Transfer(from, to, amount);
    }
}
