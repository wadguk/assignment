# Assignment
This contract handles subscription payments, provider earnings, and subscriber time tracking, providing flexibility for providers and ensuring that subscribers only pay for active subscriptions.
### Overview
 - Allows providers to register with a unique ID and set a monthly fee for their services
 - Supports subscribers who register and deposit tokens to subscribe to multiple providers
 - Manages subscription periods, renewals, and due dates for each subscriber-provider relationship
 - Utilizes Chainlink price feed to ensure provider fees meet a minimum USD threshold
 - Allows providers to adjust their fees, affecting only new or renewed subscriptions
 - Enables providers to withdraw accumulated earnings
 - Supports contract upgrades, with an option to permanently disable further upgrades
 ### Key Features
 - **Provider Registration**: Register providers with unique IDs and monthly fees; providers can be deactivated or removed.
 - **Subscriber Management**: Subscribers deposit tokens for time-based access, and can extend subscription duration with additional deposits.
 - **Subscription Status and Earnings**: Tracks active subscribers, calculates remaining subscription time, and allows providers to withdraw earnings.
 - **Upgrades and Price Feed**: Upgradeable contract with price feed integration to validate fees in USD terms.

 ### Run
```shell
npx hardhat compile
npx hardhat test
```
# What I would avoid doing
1. Presenting the subscriber balance within the contract (getSubscriberBalance). Instead, I’d calculate it off-chain or not use it at all, relying only on the subscription due date.

# TODO
1. Add custom errors to reduce gas cost.
2. Add pause/resume subscription functionality by counting total paused time to renew subscriptions later.
3. Add functionality to choose another payment token with different decimals (DAI used now).
4. Add unsubscribe functionality.

# BONUS SECTION
1. **Balance Management:** Currently, the subscription model divides the monthly fee into per-second charges (feePerSecond). This could be adapted to allow for smaller, more flexible billing intervals such as daily or hourly.  When a user deposits tokens, the contract can calculate the duration of the subscription based on their deposit amount. This allows more granular billing.

2. **System Scalability:** In this implementation, we could remove the restriction without affecting the system's functionality.

3. **Changing Provider Fees:** In this implementation, subscribers pay for the subscription based on the provider's fee at the time of purchase. If the provider changes the fee, the new rate will only affect the next subscription renewal. 