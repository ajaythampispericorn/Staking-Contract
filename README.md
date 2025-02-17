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

### MyCoin Module  

The MyCoin module implements a custom token with the following features:  

- Fixed initial supply of 1000000 tokens  
- Basic token operations (mint, burn, transfer)  
- Capability management for security  

### Staking Module  

The staking module implements the staking mechanism with:  
 
- Configurable rewards per second  
- Customizable staking duration  
- Early unstaking fee mechanism  
- Resource account for secure fund management  
- Event system for tracking stake/unstake activities  

### Events  

1. Staked Event : When tokens are staked  
2. Unstaked Event : When tokens are unstaked  
3. FeeWithdrawnEvent : When admin withdraws early unstaking fee  

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

```aptos move test --coverage  
```