//SPDX-License-Identifier:MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OrcaleLib} from "./libraries/OrcaleLib.sol";

/*
 * @title DSCEngine
 * @author RealGC
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */

/////////////////////
/// Errors        ///
/////////////////////
contract DSCEngine is ReentrancyGuard {
    /////////////////////
    /// Errors        ///
    /////////////////////
    error DSCEngine__MustMoreThanZero();
    error DSCEngine__NotAllowedCollateral(address _collateral);
    error DSCEngine__CollateralAndPriceFeedLengthMismatch();
    error DSCEngine__TransferFailed();
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorIsBroken();
    error DSCEngine__HealthFactorOK();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__DebtValueCollateralTooSmall();

    using OrcaleLib for AggregatorV3Interface;
    /////////////////////
    /// Events        ///
    /////////////////////

    event CollateralDeposited(address indexed user, address indexed collateral, uint256 indexed amount);
    event CollateralRedeemed(address indexed user, address indexed collateral, uint256 indexed amount);
    event LiquidationRedeemed(
        address indexed user, address indexed liquidator, address indexed collateral, uint256 amount
    );

    /////////////////////
    /// State Variables///
    /////////////////////
    DecentralizedStableCoin public immutable i_dsc;
    mapping(address collateralAddr => address priceFeedAddr) private s_priceFeed; //collateralToPriceFeed
    mapping(address user => mapping(address collateral => uint256 amount)) private s_userBalance; //userToCollateralToAmount
    mapping(address user => uint256 DSCMinted) private s_userToDSCMinted;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //50%mintRate,200%overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant BOUNS_SHARE = 10; //10%
    uint256 private constant BOUNS_PRECISION = 100;

    address[] private s_collateralAddresses;

    /////////////////////
    /// Modifiers     ///
    /////////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) revert DSCEngine__MustMoreThanZero();
        _;
    }

    modifier AllowedCollateral(address _collateral) {
        if (s_priceFeed[_collateral] == address(0)) revert DSCEngine__NotAllowedCollateral(_collateral);
        _;
    }

    /////////////////////
    /// Constructor   ///
    /////////////////////
    constructor(address dscAddress, address[] memory collateralAddresses, address[] memory priceFeedAddresses) {
        i_dsc = DecentralizedStableCoin(dscAddress);
        if (collateralAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__CollateralAndPriceFeedLengthMismatch();
        }
        for (uint256 i = 0; i < collateralAddresses.length; i++) {
            s_priceFeed[collateralAddresses[i]] = priceFeedAddresses[i];
            s_collateralAddresses.push(collateralAddresses[i]);
        }
    }
    ////////////////////////
    ////////////////////////

    /////////////////////
    /// External Functions ///
    /////////////////////
    /**
     * @notice This function will deposit your collateral and mint DSC in one transaction
     * @notice This is a function combine deposite collaternal and mint dsc
     * @param _collateral The collaternal address they want to deposite
     * @param _amountToDeposit The collaternal amount they want to deposite
     * @param _amountDscToMint The DSC amount they want to mint
     */
    function depositCollateralAndMintDSC(address _collateral, uint256 _amountToDeposit, uint256 _amountDscToMint)
        external
    {
        depositCollateral(_collateral, _amountToDeposit);
        mintDSC(_amountDscToMint);
    }

    /**
     * @notice Deposits collateral into the system
     * @param _collateral The address of the collateral to deposit
     * @param _amount The amount of collateral to deposit
     */
    function depositCollateral(address _collateral, uint256 _amount)
        public
        moreThanZero(_amount)
        AllowedCollateral(_collateral)
    {
        s_userBalance[msg.sender][_collateral] += _amount;
        emit CollateralDeposited(msg.sender, _collateral, _amount);
        bool success = IERC20(_collateral).transferFrom(msg.sender, address(this), _amount);
        if (!success) revert DSCEngine__TransferFailed();
    }

    /**
     * @notice Allows a user to redeem collateral and burn DSC in one transaction
     * @param _amountCollateralToRedeem The amount of collateral to redeem
     * @param _collateral The address of the collateral to redeem
     * @param _amountDscToBurn The amount of DSC to burn
     */
    function redeemCollateralForDSC(uint256 _amountCollateralToRedeem, address _collateral, uint256 _amountDscToBurn)
        external
        nonReentrant
    {
        redeemCollateral(_amountCollateralToRedeem, _collateral);
        burnDSC(_amountDscToBurn);
    }

    /**
     * @notice Allows a user to redeem their collateral
     * @param _amount The amount of collateral to redeem
     * @param _collateral The address of the collateral token to redeem
     */
    function redeemCollateral(uint256 _amount, address _collateral) public moreThanZero(_amount) nonReentrant {
        _redeemCollateral(_amount, _collateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Allows a user to mint DSC
     * @param _amountDSCToMint The amount of DSC to mint
     * @notice They must have more collateral value than the minimum threshold
     * @dev This function follows CEI pattern but checks health factor before minting
     */
    function mintDSC(uint256 _amountDSCToMint) public moreThanZero(_amountDSCToMint) nonReentrant {
        s_userToDSCMinted[msg.sender] += _amountDSCToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool success = i_dsc.mint(msg.sender, _amountDSCToMint);
        if (!success) revert DSCEngine__MintFailed();
    }

    /**
     * @notice Allows a user to burn DSC
     * @param _amount The amount of DSC to burn
     */
    function burnDSC(uint256 _amount) public moreThanZero(_amount) {
        _burnDSC(_amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // This should never hit
    }

    /**
     * @notice Allows a user to liquidate another user who has broken their health factor
     * @param _user The user to liquidate
     * @param _collateral The collateral token to liquidate
     * @param debetToCover The amount of DSC to burn to improve the users health factor
     */
    function liquidate(address _user, address _collateral, uint256 debetToCover)
        external
        moreThanZero(debetToCover)
        AllowedCollateral(_collateral)
    {
        uint256 startingHealthFactor = getHealthFactor(_user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) revert DSCEngine__HealthFactorOK();
        uint256 debetToCoverInCollateralValue = _getdebetToCoverInCollateral(_collateral, debetToCover);
        uint256 bouns = (debetToCoverInCollateralValue * BOUNS_SHARE) / BOUNS_PRECISION;
        uint256 totalToRedeem = debetToCoverInCollateralValue + bouns;
        _burnDSC(debetToCover, _user, msg.sender);
        _redeemCollateral(totalToRedeem, _collateral, _user, msg.sender);

        uint256 afterHealthFactor = _getHealthFactor(_user);
        if (afterHealthFactor < startingHealthFactor) revert DSCEngine__HealthFactorNotImproved();

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /////////////////////
    /// Public View/Pure Functions ///
    /////////////////////
    function _redeemCollateral(uint256 _amount, address _collateral, address _user, address _to) internal {
        s_userBalance[_user][_collateral] -= _amount;
        emit LiquidationRedeemed(_user, msg.sender, _collateral, _amount);
        bool success = IERC20(_collateral).transfer(_to, _amount);
        if (!success) revert DSCEngine__TransferFailed();
    }

    function _burnDSC(uint256 _amount, address _user, address _liquidator) internal {
        s_userToDSCMinted[_user] -= _amount;
        bool success = i_dsc.transferFrom(_liquidator, address(this), _amount);
        if (!success) revert DSCEngine__TransferFailed();
        i_dsc.burn(_amount);
    }

    function _getdebetToCoverInCollateral(address _collateral, uint256 debetToCover) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[_collateral]);
        int256 price = priceFeed.checkLatestPrice();
        uint256 debtValueCollateral = (debetToCover * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
        if (debtValueCollateral == 0) revert DSCEngine__DebtValueCollateralTooSmall();
        //如果数额极低，这里返回的是0
        return debtValueCollateral;
    }

    function getHealthFactor(address _user) public view returns (uint256) {
        return _getHealthFactor(_user);
    }

    /////////////////////
    /// Internal & Private Functions ///
    /////////////////////
    function _revertIfHealthFactorIsBroken(address _user) internal view {
        if (_getHealthFactor(_user) < MIN_HEALTH_FACTOR) revert DSCEngine__HealthFactorIsBroken();
    }

    function _getHealthFactor(address _user) internal view returns (uint256) {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUSD) = _getAccountInformation(_user);
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collaternalAdjustedForLiquidationThreshold =
            (totalCollateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collaternalAdjustedForLiquidationThreshold * PRECISION) / totalDscMinted;
    }

    function _getAccountInformation(address _user)
        internal
        view
        returns (uint256 totaDscMinted, uint256 totalCollateralValueInUSD)
    {
        totaDscMinted = s_userToDSCMinted[_user];
        totalCollateralValueInUSD = getAccountCollateralValueInUSD(_user);
    }

    function getAccountCollateralValueInUSD(address _user) public view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 i = 0; i < s_collateralAddresses.length; i++) {
            address collateral = s_collateralAddresses[i];
            totalCollateralValueInUSD += getUsdValue(collateral, s_userBalance[_user][collateral]);
        }
        return totalCollateralValueInUSD;
    }

    function getUsdValue(address _collateral, uint256 _amount) public view returns (uint256) {
        (, int256 price,,,) = AggregatorV3Interface(s_priceFeed[_collateral]).latestRoundData();
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * _amount) / PRECISION;
    }

    function getUserBalance(address _user, address _collateral) external view returns (uint256) {
        return s_userBalance[_user][_collateral];
    }

    function getCollateralAddresses() external view returns (address[] memory) {
        return s_collateralAddresses;
    }

    function getPriceFeedAddresses(uint256 _index) external view returns (address) {
        return s_priceFeed[s_collateralAddresses[_index]];
    }

    function getUserToMinted(address _user) external view returns (uint256) {
        return s_userToDSCMinted[_user];
    }
}
