// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./IServiceHub.sol";

/**
 * @title ServiceHub - Subscription Management Smart Contract
 * @notice This contract handles subscription payments, provider earnings, and subscriber time tracking, 
 *         providing flexibility for providers and ensuring that subscribers only pay for active subscriptions.
 */
contract ServiceHub is IServiceHub, UUPSUpgradeable, OwnableUpgradeable {
    using EnumerableSet for EnumerableSet.UintSet;

    IERC20 public token;
    AggregatorV2V3Interface public priceFeed;

    uint256 public constant MIN_PROVIDER_FEE_USD = 50 * 1e18;   // $50 in USD
    uint256 public constant MAX_PROVIDERS = 200;                // No need in this implementation
    uint256 public constant MAX_SUBSCRIBED_PROVIDERS = 20;      // To avoid problems with gas when getting balance
    uint256 public constant MONTH_IN_SECONDS = 86400 * 30;
    
    bool public upgradesDisabledOnce;   
    uint256 public providerCount;

    struct Provider {
        address owner;
        uint256 feePerSecond;
        uint256 balance;
        bool isActive;
        EnumerableSet.UintSet activeSubscribers;
    }

    struct Subscriber {
        address owner;
        bool isPaused;
        EnumerableSet.UintSet activeProviders;
        mapping(uint256 => uint256) subscriptionDueDate;
    }

    mapping(uint256 => Provider) private _providers;
    mapping(uint256 => Subscriber) private _subscribers;

    modifier onlyProviderOwner(uint256 providerId) {
        require(_providers[providerId].owner == msg.sender, "Not the provider owner");
        _;
    }

    modifier onlySubscriberOwner(uint256 subscriberId) {
        require(_subscribers[subscriberId].owner == msg.sender, "Not the subscriber owner");
        _;
    }

    /** 
     * @notice Initializes the contract with the token and price feed addresses.
     * @param _token The address of the ERC20 token.
     * @param _priceFeed The address of the price feed contract for token price.
     */
    function initialize(IERC20 _token, AggregatorV2V3Interface _priceFeed) external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        token = _token;
        priceFeed = _priceFeed;
    }

    /** 
     * @notice Registers a new provider in the system.
     * @param providerId The unique identifier for the provider.
     * @param monthlyFee The monthly fee charged by the provider in the token's smallest unit.
     */
    function registerProvider(uint256 providerId, uint256 monthlyFee) external {
        require(providerCount < MAX_PROVIDERS, "Provider limit reached");
        require(_providers[providerId].owner == address(0), "Provider already registered");

        uint256 feeUSD = (monthlyFee * _getTokenPriceUSD()) / 1e18;
        require(feeUSD >= MIN_PROVIDER_FEE_USD, "Fee below minimum required");

        _providers[providerId].owner = msg.sender;
        _providers[providerId].feePerSecond = monthlyFee / MONTH_IN_SECONDS;
        _providers[providerId].isActive = true;

        providerCount++;

        emit ProviderRegistered(providerId, msg.sender, monthlyFee);
    }

    /** 
     * @notice Removes a provider from the system.
     * @param providerId The unique identifier of the provider to be removed.
     */
    function removeProvider(uint256 providerId) external onlyProviderOwner(providerId) {
        token.transfer(_providers[providerId].owner, _providers[providerId].balance);
        delete _providers[providerId];
        providerCount--;

        emit ProviderRemoved(providerId, msg.sender);
    }

    /** 
     * @notice Subscribes a user to a provider.
     * @param subscriberId The unique identifier for the subscriber.
     * @param providerId The unique identifier for the provider to subscribe to.
     * @param deposit The amount of tokens deposited for the subscription.
     */
    function subscribe(uint256 subscriberId, uint256 providerId, uint256 deposit) external {
        require(!EnumerableSet.contains(_subscribers[subscriberId].activeProviders, providerId), "Already registered");
        if(_subscribers[subscriberId].owner == address(0)){_subscribers[subscriberId].owner = msg.sender;}
        token.transferFrom(msg.sender, address(this), deposit);

        require(_providers[providerId].isActive, "Provider not active");
        require(EnumerableSet.length(_subscribers[subscriberId].activeProviders) < MAX_SUBSCRIBED_PROVIDERS, "Max providers limit");
        EnumerableSet.add(_providers[providerId].activeSubscribers, subscriberId);
        EnumerableSet.add(_subscribers[subscriberId].activeProviders, providerId);
        _providers[providerId].balance += deposit;
        _subscribers[subscriberId].subscriptionDueDate[providerId] = block.timestamp + deposit / _providers[providerId].feePerSecond;

        emit SubscriberRegistered(subscriberId, msg.sender, deposit);
    }

    /** 
     * @notice Increases the subscription deposit for a subscriber.
     * @param subscriberId The unique identifier for the subscriber.
     * @param providerId The unique identifier for the provider.
     * @param amount The additional amount of tokens to deposit.
     */
    function increaseSubscriptionDeposit(uint256 subscriberId, uint256 providerId, uint256 amount) external onlySubscriberOwner(subscriberId){
        require(_providers[providerId].isActive, "Provider not active");

        token.transferFrom(msg.sender, address(this), amount);
        _providers[providerId].balance += amount;

        uint256 additionalTime = amount / _providers[providerId].feePerSecond;
        _subscribers[subscriberId].subscriptionDueDate[providerId] += additionalTime;

        emit SubscriptionIncreased(subscriberId, amount);
    }

    /** 
     * @notice Sets a new monthly fee for a provider.
     * @param providerId The unique identifier for the provider.
     * @param newMonthlyFee The new monthly fee to set for the provider.
     */
    function setProviderFee(uint256 providerId, uint256 newMonthlyFee) external onlyProviderOwner(providerId) {
        require(_providers[providerId].isActive, "Provider not active");
        
        uint256 newFeeUSD = (newMonthlyFee * _getTokenPriceUSD()) / 1e18;
        require(newFeeUSD >= MIN_PROVIDER_FEE_USD, "New fee below minimum required");

        _providers[providerId].feePerSecond = newMonthlyFee / MONTH_IN_SECONDS;

        emit ProviderFeeSet(providerId, newMonthlyFee);
    }

    /** 
     * @notice Withdraws earnings from the provider's balance.
     * @param providerId The unique identifier for the provider.
     */
    function withdrawEarnings(uint256 providerId) external onlyProviderOwner(providerId) {
        uint256 earnings = _providers[providerId].balance;
        uint256 earningsUSD = (earnings * _getTokenPriceUSD()) / 1e18;
        
        _providers[providerId].balance -= earnings;
        token.transfer(msg.sender, earnings);

        emit EarningsWithdrawn(providerId, earnings, earningsUSD);
    }

    /** 
     * @notice Updates the active state of a provider.
     * @param providerId The unique identifier for the provider.
     * @param isActive The new active state of the provider.
     */
    function updateProviderState(uint256 providerId, bool isActive) external onlyOwner {
        _providers[providerId].isActive = isActive;
        emit ProviderStateUpdated(providerId, isActive);
    }

    /** 
     * @notice Disables contract upgrades.
     * @dev This function can only be called by the owner.
     */
    function disableUpgrades() external onlyOwner {
        require(!upgradesDisabledOnce, "Already disabled");
        upgradesDisabledOnce = true;
    }

    /** 
     * @notice Checks if a subscriber's subscription is still active.
     * @param subscriberId The unique identifier for the subscriber.
     * @param providerId The unique identifier for the provider.
     * @return isActive Returns true if the subscription is active, otherwise false.
     */
    function checkSubscriptionStatus(uint256 subscriberId, uint256 providerId) external view returns (bool) {
        return _subscribers[subscriberId].subscriptionDueDate[providerId] > block.timestamp;
    }

    /** 
     * @notice Gets the current state of a provider.
     * @param providerId The unique identifier for the provider.
     * @return owner The address of the provider's owner.
     * @return feePerSecond The fee charged per second by the provider.
     * @return balance The current balance of the provider.
     * @return isActive The active status of the provider.
     * @return activeSubscribers The list of active subscribers.
     */
    function getProviderState(uint256 providerId) external view returns (
        address owner,
        uint256 feePerSecond,
        uint256 balance,
        bool isActive,
        uint256[] memory activeSubscribers
    ) {
        return (
            _providers[providerId].owner,
            _providers[providerId].feePerSecond,
            _providers[providerId].balance,
            _providers[providerId].isActive,
            EnumerableSet.values(_providers[providerId].activeSubscribers)
        );
    }

    /**
     * @notice Retrieves the current earnings of a specified provider.
     * @dev This function returns the total balance accumulated by the provider,
     *      which can be withdrawn by the provider owner.
     * @param providerId The unique identifier for the provider whose earnings are being retrieved.
     * @return balance The total earnings of the provider, represented in the smallest unit of the token.
     */
    function getProviderEarnings(uint256 providerId) external view returns (uint256) {
        return _providers[providerId].balance;
    }

    /** 
     * @notice Gets the current state of a subscriber.
     * @param subscriberId The unique identifier for the subscriber.
     * @return owner The address of the subscriber's owner.
     * @return balance The total balance of the subscriber.
     * @return isPaused The paused status of the subscriber.
     * @return activeProviders The count of active providers for the subscriber.
     */
    function getSubscriberState(uint256 subscriberId) external view returns (
        address owner,
        uint256 balance,
        bool isPaused,
        uint256[] memory activeProviders

    ) {
        return (
            _subscribers[subscriberId].owner,
            getSubscriberBalance(subscriberId),
            _subscribers[subscriberId].isPaused,
            EnumerableSet.values(_subscribers[subscriberId].activeProviders)
        );
    }
    
    /** 
     * @notice Retrieves the total deposit value of a subscriber in USD.
     * @dev The value is calculated by multiplying the subscriber's balance by the current token price in USD.
     * @param subscriberId The unique identifier for the subscriber.
     * @return depositValueUSD The total deposit value of the subscriber in USD, represented with 18 decimals.
     */
    function getSubscriberDepositValueUSD(uint256 subscriberId) external view returns (uint256) {
        return (getSubscriberBalance(subscriberId) * _getTokenPriceUSD()) / 1e18;
    }

    /** 
     * @notice Calculates the total balance of a subscriber across all active subscriptions.
     * @dev The balance is computed by summing the remaining time for each active subscription multiplied 
     *      by the corresponding provider's fee per second. Only subscriptions that are still active 
     *      (i.e., not expired) are included in the calculation.
     * @param subscriberId The unique identifier for the subscriber.
     * @return balance The total balance of the subscriber, represented in the smallest unit of the token.
     */
    function getSubscriberBalance(uint256 subscriberId) public view returns (uint256 balance) {
        for (uint i = 0; i < EnumerableSet.length(_subscribers[subscriberId].activeProviders); i++) {
            uint256 providerId = EnumerableSet.at(_subscribers[subscriberId].activeProviders, i);
            
            // Check if the subscription is still active
            if (_subscribers[subscriberId].subscriptionDueDate[providerId] > block.timestamp) {
                uint256 remainingTime = _subscribers[subscriberId].subscriptionDueDate[providerId] - block.timestamp;
                uint256 providerFeePerSecond = _providers[providerId].feePerSecond;
                balance += remainingTime * providerFeePerSecond;
            }
        }
    }

    // solc-ignore-next-line func-mutability unused-param
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        require(!upgradesDisabledOnce, "Upgrades are disabled");
    }

    /** 
     * @notice Retrieves the current price of the token in USD.
     * @return price The current price of the token in USD with 18 decimals.
     */
    function _getTokenPriceUSD() private view returns (uint256) {
        (, int256 answer, , , ) = priceFeed.latestRoundData();
        return uint256(answer) * 1e10; // Adjust Chainlink price to 18 decimals
    }
    
}
