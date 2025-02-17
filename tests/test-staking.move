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
    const EINVALID_FEE_COLLECTOR: u64 = 100;

    fun setup(aptos_framework: &signer): (signer, signer, signer) {
        // Set up initial blockchain state
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        // Create test accounts
        let admin = account::create_account_for_test(@staking);  // Using staking address for admin
        let user = account::create_account_for_test(@0xB0B);
        let fee_collector = account::create_account_for_test(@0xC0FFEE);
        
        // Initialize MyCoin
        mycoin::initialize(&admin);
        
        // Register users for MyCoin
        mycoin::register(&user);
        mycoin::register(&fee_collector);
        
        // Transfer some coins to user for testing
        coin::transfer<MyCoin>(&admin, signer::address_of(&user), INITIAL_STAKE);
        
        (admin, user, fee_collector)
    }

    #[test]
    fun test_mycoin_initialization() {
        let admin = account::create_account_for_test(@staking);
        
        // Initialize MyCoin
        mycoin::initialize(&admin);
        
        // Verify admin has MyCoin capability and coins
        assert!(coin::is_account_registered<MyCoin>(signer::address_of(&admin)), 1);
        assert!(coin::balance<MyCoin>(signer::address_of(&admin)) == 1_000_000, 2);
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
    fun test_initialization() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (admin, _user, fee_collector) = setup(&aptos_framework);
        
        staking::initialize(
            &admin,
            REWARDS_PER_SECOND,
            DURATION,
            EARLY_UNSTAKE_FEE,
            signer::address_of(&fee_collector)
        );
    }

    #[test]
    fun test_stake_success() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (admin, user, fee_collector) = setup(&aptos_framework);
        
        staking::initialize(
            &admin,
            REWARDS_PER_SECOND,
            DURATION,
            EARLY_UNSTAKE_FEE,
            signer::address_of(&fee_collector)
        );
        
        staking::stake(&user, STAKE_AMOUNT);
    }

    #[test]
    fun test_unstake_after_duration() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (admin, user, fee_collector) = setup(&aptos_framework);
        
        staking::initialize(
            &admin,
            REWARDS_PER_SECOND,
            DURATION,
            EARLY_UNSTAKE_FEE,
            signer::address_of(&fee_collector)
        );
        
        staking::stake(&user, STAKE_AMOUNT);
        
        // Fast forward time beyond duration
        timestamp::fast_forward_seconds(DURATION + 1);
        
        staking::unstake(&user);
    }

    #[test]
    fun test_early_unstake_with_fee() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (admin, user, fee_collector) = setup(&aptos_framework);
        
        staking::initialize(
            &admin,
            REWARDS_PER_SECOND,
            DURATION,
            EARLY_UNSTAKE_FEE,
            signer::address_of(&fee_collector)
        );
        
        staking::stake(&user, STAKE_AMOUNT);
        
        // Fast forward time but not beyond duration
        timestamp::fast_forward_seconds(DURATION / 2);
        
        staking::unstake(&user);
    }

    #[test]
    fun test_withdraw_fees() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (admin, user, fee_collector) = setup(&aptos_framework);
        
        staking::initialize(
            &admin,
            REWARDS_PER_SECOND,
            DURATION,
            EARLY_UNSTAKE_FEE,
            signer::address_of(&fee_collector)
        );
        
        staking::stake(&user, STAKE_AMOUNT);
        
        // Early unstake to generate fees
        timestamp::fast_forward_seconds(DURATION / 2);
        staking::unstake(&user);
        
        staking::withdraw_fees(&fee_collector);
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_FEE_COLLECTOR, location = staking)]
    fun test_withdraw_fees_unauthorized() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (admin, user, fee_collector) = setup(&aptos_framework);
        
        staking::initialize(
            &admin,
            REWARDS_PER_SECOND,
            DURATION,
            EARLY_UNSTAKE_FEE,
            signer::address_of(&fee_collector)
        );
        
        // Try to withdraw fees with unauthorized account (using user instead of fee_collector)
        staking::withdraw_fees(&user);
    }

    #[test]
    fun test_multiple_stakes_and_unstakes() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (admin, user, fee_collector) = setup(&aptos_framework);
        
        staking::initialize(
            &admin,
            REWARDS_PER_SECOND,
            DURATION,
            EARLY_UNSTAKE_FEE,
            signer::address_of(&fee_collector)
        );
        
        // First stake
        staking::stake(&user, STAKE_AMOUNT / 2);
        
        // Fast forward some time
        timestamp::fast_forward_seconds(DURATION / 4);
        
        // Second stake
        staking::stake(&user, STAKE_AMOUNT / 2);
        
        // Fast forward beyond duration
        timestamp::fast_forward_seconds(DURATION);
        
        // Unstake all
        staking::unstake(&user);
    }

    #[test]
    fun test_zero_stake() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (admin, user, fee_collector) = setup(&aptos_framework);
        
        staking::initialize(
            &admin,
            REWARDS_PER_SECOND,
            DURATION,
            EARLY_UNSTAKE_FEE,
            signer::address_of(&fee_collector)
        );
        
        staking::stake(&user, 0);
    }

    #[test]
    fun test_stake_exact_duration() {
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let (admin, user, fee_collector) = setup(&aptos_framework);
        
        staking::initialize(
            &admin,
            REWARDS_PER_SECOND,
            DURATION,
            EARLY_UNSTAKE_FEE,
            signer::address_of(&fee_collector)
        );
        
        staking::stake(&user, STAKE_AMOUNT);
        
        // Fast forward exactly to duration
        timestamp::fast_forward_seconds(DURATION);
        
        staking::unstake(&user);
    }
}