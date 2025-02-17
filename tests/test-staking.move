#[test_only]
module staking::staking_tests {
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use staking::staking;
    use staking::mycoin::{Self, MyCoin};

    // Test constants
    const REWARDS_PER_SECOND: u64 = 10;
    const DURATION: u64 = 100;
    const EARLY_UNSTAKE_FEE: u64 = 10; // 10%
    const INITIAL_STAKE: u64 = 1000;
    const STAKE_AMOUNT: u64 = 500;

    // Error codes
    const INVALID_ADMIN: u64 = 1;

    fun setup(aptos_framework: &signer): (signer, signer) {
    timestamp::set_time_has_started_for_testing(aptos_framework);
    
    let admin = account::create_account_for_test(@staking);
    let user = account::create_account_for_test(@0xB0B);
    
    mycoin::initialize(&admin);
    mycoin::register(&user);
    
    coin::transfer<MyCoin>(&admin, signer::address_of(&user), INITIAL_STAKE);
    
    (admin, user)
    }

    #[test]
    fun test_initialization() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (admin, _user) = setup(&aptos_framework);
    
        staking::initialize(
            &admin,
            REWARDS_PER_SECOND,
            DURATION,
            EARLY_UNSTAKE_FEE
        );
    }

    #[test]
    fun test_mycoin_registration() {
        let admin = account::create_account_for_test(@staking);
        let user = account::create_account_for_test(@0xB0B);
        
        // Initialize MyCoin
        mycoin::initialize(&admin);
        
        // Register user
        mycoin::register(&user);
        assert!(coin::is_account_registered<MyCoin>(signer::address_of(&user)), 3);
        assert!(coin::balance<MyCoin>(signer::address_of(&user)) == 0, 4);
    }

    #[test]
    fun test_mycoin_transfer() {
        let admin = account::create_account_for_test(@staking);
        let user = account::create_account_for_test(@0xB0B);
        
        // Initialize MyCoin
        mycoin::initialize(&admin);
        
        // Register user
        mycoin::register(&user);
        
        // Transfer coins
        let transfer_amount = 100000;
        let coins = coin::withdraw<MyCoin>(&admin, transfer_amount);
        coin::deposit(signer::address_of(&user), coins);
        
        assert!(coin::balance<MyCoin>(signer::address_of(&user)) == transfer_amount, 5);
        assert!(coin::balance<MyCoin>(signer::address_of(&admin)) == 1_000_000 - transfer_amount, 6);
    }

    #[test]
    fun test_stake_success() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (admin, user) = setup(&aptos_framework);
    
        staking::initialize(
            &admin,
            REWARDS_PER_SECOND,
            DURATION,
            EARLY_UNSTAKE_FEE
        );
    
        staking::stake(&user, STAKE_AMOUNT);    
    }


    #[test]
    fun test_unstake_after_duration() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (admin, user) = setup(&aptos_framework);
    
        staking::initialize(
            &admin,
            REWARDS_PER_SECOND,
            DURATION,
            EARLY_UNSTAKE_FEE
        );
    
        staking::stake(&user, STAKE_AMOUNT);
    
        timestamp::fast_forward_seconds(DURATION + 1);
    
        staking::unstake(&user);
    }

    #[test]
    fun test_early_unstake_with_fee() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (admin, user) = setup(&aptos_framework);
    
        staking::initialize(
            &admin,
            REWARDS_PER_SECOND,
            DURATION,
            EARLY_UNSTAKE_FEE
        );
    
        staking::stake(&user, STAKE_AMOUNT);
    
        timestamp::fast_forward_seconds(DURATION / 2);
    
        staking::unstake(&user);
    }

    #[test]
    fun test_withdraw_fees() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (admin, user) = setup(&aptos_framework);
    
        staking::initialize(
            &admin,
            REWARDS_PER_SECOND,
            DURATION,
            EARLY_UNSTAKE_FEE
        );
    
        staking::stake(&user, STAKE_AMOUNT);
    
        timestamp::fast_forward_seconds(DURATION / 2);
        staking::unstake(&user);
    
        staking::withdraw_fees(&admin);
    }

    #[test]
    #[expected_failure(abort_code = INVALID_ADMIN, location = staking)]
    fun test_withdraw_fees_unauthorized() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (admin, user) = setup(&aptos_framework);
    
        staking::initialize(
            &admin,
            REWARDS_PER_SECOND,
            DURATION,
            EARLY_UNSTAKE_FEE
        );
    
        staking::withdraw_fees(&user);
    }

    #[test]
    fun test_multiple_stakes_and_unstakes() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (admin, user) = setup(&aptos_framework);
    
        staking::initialize(
            &admin,
            REWARDS_PER_SECOND,
            DURATION,
            EARLY_UNSTAKE_FEE
        );
    
    // First stake
        staking::stake(&user, STAKE_AMOUNT / 2);
    
        timestamp::fast_forward_seconds(DURATION / 4);
    
    // Second stake
        staking::stake(&user, STAKE_AMOUNT / 2);
    
        timestamp::fast_forward_seconds(DURATION);
    
    // Unstake all
        staking::unstake(&user);
    }

    #[test]
    fun test_zero_stake() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (admin, user) = setup(&aptos_framework);
    
        staking::initialize(
            &admin,
            REWARDS_PER_SECOND,
            DURATION,
            EARLY_UNSTAKE_FEE
        );
    
        staking::stake(&user, 0);   
    }

    #[test]
    fun test_stake_exact_duration() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (admin, user) = setup(&aptos_framework);
    
        staking::initialize(
            &admin,
            REWARDS_PER_SECOND,
            DURATION,
            EARLY_UNSTAKE_FEE
        );
    
        staking::stake(&user, STAKE_AMOUNT);
    
      timestamp::fast_forward_seconds(DURATION);
    
        staking::unstake(&user);
    }
}