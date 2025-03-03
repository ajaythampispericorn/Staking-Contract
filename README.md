# STAKING CONTRACT WITH MULTIPLE USERS AND MYCOIN FUNGIBLE ASSET  

A staking system implemented on Aptos Blockchain using a custom fungible asset, MyCoin, that allows users to stake the tokens and claim rewards. It includes different users such as staker and an admin. It allows different features such as staking, early unstaking with a fee, reward distribution and comprehensive testing.  

## Features  

- Custom token (MyCoin) implementation  
- Flexible staking and unstaking mechanisms  
- Time-based reward distribution system  
- Early unstaking fee mechanism  
- Admin-controlled fee withdrawal  
- Event emission for tracking activities  
- Resource account management  

## Pre-requisites  

- Aptos CLI  
- Move Compiler  

## Smart Contract Details  

### Roles Module  

The roles module is responsible for role management within a staking system. It defines and enforces access control by assigning specific roles to different addresses.  

- Pool Admin: The highest authority, capable of updating all roles  
- Fee Manager: Handles fees within the staking system  
- Reward Manager: Manages reward distribution  
- Fee Collector: Receives collected fees

### MyCoin Module  

The MyCoin module implements a custom token with the following features:  

- Custom Coin Implementation : Defines MyCoin as a custom fungible asset  
- One-Time Initialization : Ensures the module is initialized only once by the admin  
- Minting Capability : Allows the admin to mint new coins  
- Token Registration : Users can register their accounts to hold MyCoin  
- Coin Transfers : Enables users to transfer MyCoin to other accounts  
- Balance Query : Provides a way to check an account's MyCoin balance  
- Access Control : Only the admin (deployer) has minting rights  
- Storage of Capabilities : Keeps mint, burn, and freeze capabilities securely stored  

### Staking Module  

The staking module implements the staking mechanism with:  
 
- Staking & Unstaking: Users can stake and unstake tokens with restrictions on amounts and time periods  
- Reward Mechanism: Users earn rewards based on the amount staked and the duration of staking  
- Fee System: Early unstaking incurs fees with configurable parameters  
- Admin Controls: Admins can update pool parameters, manage fees, and lock/unlock rewards  
- Event Emission: Key actions such as staking, unstaking, and claiming rewards generate events for      tracking  

### Events  

1. StakedEvent: Emitted when a user stakes tokens  
2. UnstakedEvent: Emitted when a user withdraws tokens  
3. RewardClaimEvent: Emitted when a user claims rewards  
4. FeeEvent: Emitted on fee transactions  
5. PoolUpdateEvent: Emitted when pool configurations change  

## Aptos CLI Installation  

Go to Aptos [CLI release page](https://github.com/aptos-labs/aptos-core/releases?q=cli&expanded=true)  
Follow the instructions given to install Aptos CLI  

To verify installation  

```  
aptos --version  
```  

## Setup CLI Configuration  

Run the command  
```
aptos init  
```  

To use default settings, you can provide no input and just press “Enter”.  

## To Compile  

```  
aptos move compile  
```  

## To Test  

1. To test  

```  
aptos move test  
```  

2. To find test coverage  

```  
aptos move test --coverage  
```