// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";

interface IServiceHub {
    // Events
    event ProviderRegistered(uint256 indexed providerId, address owner, uint256 fee);
    event ProviderRemoved(uint256 indexed providerId, address owner);
    event SubscriberRegistered(uint256 indexed subscriberId, address owner, uint256 deposit);
    event SubscriptionIncreased(uint256 indexed subscriberId, uint256 amount);
    event EarningsWithdrawn(uint256 indexed providerId, uint256 tokenAmount, uint256 usdValue);
    event ProviderStateUpdated(uint256 indexed providerId, bool isActive);
    event ProviderFeeSet(uint256 indexed providerId, uint256 newMonthlyFee);

    function initialize(IERC20 _token, AggregatorV2V3Interface _priceFeed) external;
    
    function registerProvider(uint256 providerId, uint256 monthlyFee) external;
    
    function removeProvider(uint256 providerId) external;
    
    function subscribe(uint256 subscriberId, uint256 providerId, uint256 deposit) external;
    
    function increaseSubscriptionDeposit(uint256 subscriberId, uint256 providerId, uint256 amount) external;

    function setProviderFee(uint256 providerId, uint256 newMonthlyFee) external;
    
    function withdrawEarnings(uint256 providerId) external;

    function updateProviderState(uint256 providerId, bool isActive) external;
    
    function checkSubscriptionStatus(uint256 subscriberId, uint256 providerId) external view returns (bool);

    function disableUpgrades() external;

    function getProviderState(uint256 providerId) external view returns (
        address owner,
        uint256 feePerSecond,
        uint256 balance,
        bool isActive,
        uint256[] memory activeSubscribers
    );

    function getProviderEarnings(uint256 providerId) external view returns (uint256);
    
    function getSubscriberState(uint256 subscriberId) external view returns (
        address owner,
        uint256 balance,
        uint256[] memory activeProviders,
        bool isPaused
    );

    function getSubscriberBalance(uint256 subscriberId) external view returns (uint256);

    function getSubscriberDepositValueUSD(uint256 subscriberId) external view returns (uint256);
}
