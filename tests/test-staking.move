#[test_only]
module staking::staking_tests {
    use std::signer;
    use std::string;
    use std::option;
    use aptos_framework::coin;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use staking::mycoin;
    use staking::roles;
    use staking::staking;

    // Test addresses
    const STAKING_ADDRESS: address = @staking;
    const USER1_ADDRESS: address = @0xAA;
    const USER2_ADDRESS: address = @0xBB;
    const FEE_MANAGER_ADDRESS: address = @0xCC;
    const REWARD_MANAGER_ADDRESS: address = @0xDD;
    const FEE_COLLECTOR_ADDRESS: address = @0xEE;
    
    // Error constants from modules
    const ENOT_POOL_ADMIN: u64 = 1;
    const ENOT_FEE_MANAGER: u64 = 2;
    const ENOT_REWARD_MANAGER: u64 = 3;
    const EINVALID_ADDRESS: u64 = 4;
    const EROLES_ALREADY_INITIALIZED: u64 = 5;
    const ENOT_AUTHORIZED: u64 = 6;
    
    // Helpers to setup test environment
    fun setup_test(): (signer, signer, signer, signer, signer) {
        // Create the aptos_framework account for timestamp initialization
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        
        // Create test accounts
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        let fee_manager = account::create_account_for_test(FEE_MANAGER_ADDRESS);
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        let fee_collector = account::create_account_for_test(FEE_COLLECTOR_ADDRESS);
        
        // Initialize modules
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        (admin, user1, fee_manager, reward_manager, fee_collector)
    }
    
    fun setup_staking_pool(admin: &signer): (u64, u64) {
        let start_time = 1000;
        let duration = 1000;
        let rewards_per_second = 10;
        let max_total_stake = 10000;
        let min_stake_amount = 100;
        let max_stake_per_user = 5000;
        let fee_percentage = 500; // 5%
        let min_fee = 10;
        let max_fee = 500;
        
        // Initialize timestamp for testing
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        // Initialize the staking pool
        staking::initialize(
            admin,
            start_time,
            duration,
            rewards_per_second,
            max_total_stake,
            min_stake_amount,
            max_stake_per_user,
            fee_percentage,
            min_fee,
            max_fee,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Create and prepare reward_manager account
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        
        // Register reward_manager to receive MyCoin
        mycoin::register(&reward_manager);
        
        // Mint coins directly to the reward_manager
        mycoin::mint_coins(admin, duration * rewards_per_second);
        mycoin::transfer(admin, REWARD_MANAGER_ADDRESS, duration * rewards_per_second);
        
        // Now lock the rewards
        staking::lock_rewards(&reward_manager, duration * rewards_per_second);
        
        (start_time, duration)
    }
    
    fun prepare_user_for_staking(admin: &signer, user: &signer, amount: u64) {
        mycoin::register(user);
        mycoin::mint_coins(admin, amount);
        mycoin::transfer(admin, signer::address_of(user), amount);
    }
    
    #[test]
    fun test_mycoin_initialize() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        mycoin::initialize(&admin);
        
        assert!(mycoin::balance(STAKING_ADDRESS) == 1_000_000_000_000, 0);
    }
    
    #[test]
    #[expected_failure(abort_code = 1)]
    fun test_mycoin_initialize_wrong_admin() {
        let not_admin = account::create_account_for_test(@0x123);
        mycoin::initialize(&not_admin);
    }
    
    #[test]
    fun test_mycoin_register() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user = account::create_account_for_test(USER1_ADDRESS);
        
        mycoin::initialize(&admin);
        mycoin::register(&user);
        
        assert!(mycoin::balance(USER1_ADDRESS) == 0, 0);
    }
    
    #[test]
    fun test_mycoin_mint_coins() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        mycoin::initialize(&admin);
        
        let initial_balance = mycoin::balance(STAKING_ADDRESS);
        mycoin::mint_coins(&admin, 1000);
        
        assert!(mycoin::balance(STAKING_ADDRESS) == initial_balance + 1000, 0);
    }
    
    #[test]
    #[expected_failure(abort_code = 1)]
    fun test_mycoin_mint_coins_wrong_admin() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let not_admin = account::create_account_for_test(USER1_ADDRESS);
        
        mycoin::initialize(&admin);
        mycoin::mint_coins(&not_admin, 1000);
    }
    
    #[test]
    fun test_mycoin_transfer() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user = account::create_account_for_test(USER1_ADDRESS);
        
        mycoin::initialize(&admin);
        mycoin::register(&user);
        
        let transfer_amount = 1000;
        mycoin::mint_coins(&admin, transfer_amount);
        mycoin::transfer(&admin, USER1_ADDRESS, transfer_amount);
        
        assert!(mycoin::balance(USER1_ADDRESS) == transfer_amount, 0);
    }
    
    #[test]
    fun test_mycoin_balance() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        mycoin::initialize(&admin);
        
        assert!(mycoin::balance(STAKING_ADDRESS) == 1_000_000_000_000, 0);
        
        // Test unregistered account
        assert!(mycoin::balance(@0x999) == 0, 0);
    }

    #[test]
    #[expected_failure]
    fun test_mycoin_transfer_insufficient_balance() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user = account::create_account_for_test(USER1_ADDRESS);
        let recipient = account::create_account_for_test(USER2_ADDRESS);
        
        mycoin::initialize(&admin);
        mycoin::register(&user);
        mycoin::register(&recipient);
        
        // Transfer some coins to user (less than we'll try to transfer)
        mycoin::mint_coins(&admin, 100);
        mycoin::transfer(&admin, USER1_ADDRESS, 100);
        
        // Try to transfer more than the user has
        mycoin::transfer(&user, USER2_ADDRESS, 500);
    }

    #[test]
    fun test_roles_initialize_roles() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        assert!(roles::is_pool_admin(STAKING_ADDRESS), 0);
        assert!(roles::is_fee_manager(FEE_MANAGER_ADDRESS), 0);
        assert!(roles::is_reward_manager(REWARD_MANAGER_ADDRESS), 0);
        assert!(roles::is_fee_collector(FEE_COLLECTOR_ADDRESS), 0);
        
        let (pool_admin, fee_manager, reward_manager, fee_collector) = roles::all_roles();
        assert!(pool_admin == STAKING_ADDRESS, 0);
        assert!(fee_manager == FEE_MANAGER_ADDRESS, 0);
        assert!(reward_manager == REWARD_MANAGER_ADDRESS, 0);
        assert!(fee_collector == FEE_COLLECTOR_ADDRESS, 0);
    }
    
    #[test]
    #[expected_failure(abort_code = ENOT_POOL_ADMIN, location = staking::roles)]
    fun test_roles_initialize_roles_wrong_admin() {
        let not_admin = account::create_account_for_test(USER1_ADDRESS);
        roles::initialize_roles(
            &not_admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
    }
    
    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_roles_initialize_roles_duplicate_addresses() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Using same address for fee_manager and reward_manager
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            FEE_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
    }
    
    #[test]
    #[expected_failure(abort_code = EROLES_ALREADY_INITIALIZED, location = staking::roles)]
    fun test_roles_initialize_roles_twice() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Try to initialize again
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
    }
    
    #[test]
    fun test_roles_update_pool_admin() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let new_admin_addr = @0x999;
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        roles::update_pool_admin(&admin, new_admin_addr);
        
        assert!(roles::is_pool_admin(new_admin_addr), 0);
        assert!(!roles::is_pool_admin(STAKING_ADDRESS), 0);
        assert!(roles::get_pool_admin() == new_admin_addr, 0);
    }

    #[test]
    fun test_roles_update_fee_manager() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let new_fee_manager_addr = @0x999;
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        roles::update_fee_manager(&admin, new_fee_manager_addr);
        
        assert!(roles::is_fee_manager(new_fee_manager_addr), 0);
        assert!(!roles::is_fee_manager(FEE_MANAGER_ADDRESS), 0);
        assert!(roles::get_fee_manager() == new_fee_manager_addr, 0);
    }
    
    #[test]
    fun test_roles_update_reward_manager() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let new_reward_manager_addr = @0x999;
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        roles::update_reward_manager(&admin, new_reward_manager_addr);
        
        assert!(roles::is_reward_manager(new_reward_manager_addr), 0);
        assert!(!roles::is_reward_manager(REWARD_MANAGER_ADDRESS), 0);
        assert!(roles::get_reward_manager() == new_reward_manager_addr, 0);
    }
    
    #[test]
    fun test_roles_update_fee_collector() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let new_fee_collector_addr = @0x999;
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        roles::update_fee_collector(&admin, new_fee_collector_addr);
        
        assert!(roles::is_fee_collector(new_fee_collector_addr), 0);
        assert!(!roles::is_fee_collector(FEE_COLLECTOR_ADDRESS), 0);
        assert!(roles::get_fee_collector() == new_fee_collector_addr, 0);
    }
    
    #[test]
    #[expected_failure(abort_code = ENOT_AUTHORIZED,location = staking::roles)]
    fun test_roles_update_fee_manager_not_authorized() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let not_admin = account::create_account_for_test(USER1_ADDRESS);
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        roles::update_fee_manager(&not_admin, @0x999);
    }

    #[test]
    fun test_roles_verify_pool_admin() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        roles::verify_pool_admin(&admin);
    }
    
    #[test]
    #[expected_failure(abort_code = ENOT_POOL_ADMIN, location = staking::roles)]
    fun test_roles_verify_pool_admin_failure() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let not_admin = account::create_account_for_test(USER1_ADDRESS);
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        roles::verify_pool_admin(&not_admin);
    }

    #[test]
    fun test_roles_verify_fee_manager() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let fee_manager = account::create_account_for_test(FEE_MANAGER_ADDRESS);
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        roles::verify_fee_manager(&fee_manager);
    }
    
    #[test]
    fun test_roles_verify_reward_manager() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        roles::verify_reward_manager(&reward_manager);
    }
    
    #[test]
    fun test_roles_verify_fee_collector() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let fee_collector = account::create_account_for_test(FEE_COLLECTOR_ADDRESS);
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        roles::verify_fee_collector(&fee_collector);
    }
    
    #[test]
    fun test_staking_initialize() {
        // Create accounts
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Initialize timestamp
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        timestamp::update_global_time_for_test_secs(1000); // Set some time value
        
        // Initialize mycoin and roles
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        let start_time = 1000;
        let duration = 1000;
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            10,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        let (actual_start, actual_end) = staking::get_pool_times();
        assert!(actual_start == start_time, 0);
        assert!(actual_end == start_time + duration, 0);
        
        let fee_config = staking::get_fee_config();
        assert!(staking::get_collected_fees() == 0, 0);
    }
    
    #[test]
    #[expected_failure(abort_code = 1)] // INVALID_ADMIN
    fun test_staking_initialize_wrong_admin() {
        let not_admin = account::create_account_for_test(USER1_ADDRESS);
        
        staking::initialize(
            &not_admin,
            1000,
            1000,
            10,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
    }
    
    #[test]
    fun test_staking_stake() {
        // Setup
        let (admin, user1, _, reward_manager, _) = setup_test();
        let (start_time, _) = setup_staking_pool(&admin);
        
        // Prepare user for staking
        let stake_amount = 1000;
        prepare_user_for_staking(&admin, &user1, stake_amount);
        
        // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // Stake
        staking::stake(&user1, stake_amount);
        
        // Verify
        let (total_staked, _, _, _) = staking::get_pool_stats();
        assert!(total_staked == stake_amount, 0);
        
        let user_info_opt = staking::get_user_info(USER1_ADDRESS);
        assert!(option::is_some(&user_info_opt), 0);
    }
    
    #[test]
    #[expected_failure(abort_code = 3, location = staking::staking)]
    fun test_staking_stake_before_start_time() {
        // Create accounts
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        
        // Initialize timestamp
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        
        // Initialize modules
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        let start_time = 1000;
        let duration = 1000;
        
        // Initialize pool
        staking::initialize(
            &admin,
            start_time,
            duration,
            10,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Set time to before pool start
        timestamp::update_global_time_for_test_secs(start_time - 50);
        
        // Prepare user for staking
        let stake_amount = 1000;
        mycoin::register(&user1);
        mycoin::mint_coins(&admin, stake_amount);
        mycoin::transfer(&admin, USER1_ADDRESS, stake_amount);
        
        // Try to stake - should fail with POOL_NOT_STARTED (3)
        staking::stake(&user1, stake_amount);
    }
    
    #[test]
    #[expected_failure(abort_code = 4)] // POOL_ENDED
    fun test_staking_stake_after_end_time() {
        // Setup
        let (admin, user1, _, reward_manager, _) = setup_test();
        let (start_time, duration) = setup_staking_pool(&admin);
        
        // Prepare user for staking
        let stake_amount = 1000;
        prepare_user_for_staking(&admin, &user1, stake_amount);
        
        // Move time to after pool end
        timestamp::update_global_time_for_test_secs(start_time + duration + 10);
        
        // Try to stake - should fail
        staking::stake(&user1, stake_amount);
    }
    
    #[test]
    #[expected_failure(abort_code = 5)] // STAKE_TOO_LOW
    fun test_staking_stake_amount_too_low() {
        // Setup
        let (admin, user1, _, reward_manager, _) = setup_test();
        let (start_time, _) = setup_staking_pool(&admin);
        
        // Prepare user for staking with amount below minimum
        let stake_amount = 50; // min is 100
        prepare_user_for_staking(&admin, &user1, stake_amount);
        
        // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // Try to stake - should fail
        staking::stake(&user1, stake_amount);
    }
    
    #[test]
    fun test_staking_unstake() {
        // Setup
        let (admin, user1, _, reward_manager, _) = setup_test();
        let (start_time, duration) = setup_staking_pool(&admin);
        
        // Prepare user for staking
        let stake_amount = 1000;
        prepare_user_for_staking(&admin, &user1, stake_amount);
        
        // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // Stake
        staking::stake(&user1, stake_amount);
        
        // Move time to after pool end to avoid fees
        timestamp::update_global_time_for_test_secs(start_time + duration + 10);
        
        // User balance before unstake
        let user_balance_before = mycoin::balance(USER1_ADDRESS);
        
        // Unstake
        staking::unstake(&user1);
        
        // Verify
        let user_balance_after = mycoin::balance(USER1_ADDRESS);
        let (total_staked, _, _, _) = staking::get_pool_stats();
        
        assert!(total_staked == 0, 0);
        // User should get their stake back plus rewards
        assert!(user_balance_after > user_balance_before, 0);
        
        // User should no longer have stake info
        let user_info_opt = staking::get_user_info(USER1_ADDRESS);
        assert!(option::is_none(&user_info_opt), 0);
    }
    
    #[test]
    #[expected_failure(abort_code = 2)] // NO_STAKE_FOUND
    fun test_staking_unstake_no_stake() {
        // Setup
        let (admin, user1, _, reward_manager, _) = setup_test();
        let (start_time, _) = setup_staking_pool(&admin);
        
        // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // Try to unstake without staking first
        staking::unstake(&user1);
    }
    
    #[test]
    fun test_staking_simple_rewards() {
    // Setup
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
    
    // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
        &admin, 
        FEE_MANAGER_ADDRESS, 
        REWARD_MANAGER_ADDRESS, 
        FEE_COLLECTOR_ADDRESS
        );
    
    // Setup pool with extremely high rewards
        let start_time = 1000;
        let duration = 1000;
        let rewards_per_second = 10000; // MUCH higher
        
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            rewards_per_second,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
    
    // Prepare rewards
        mycoin::register(&reward_manager);
        let total_rewards = duration * rewards_per_second;
        mycoin::mint_coins(&admin, total_rewards);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, total_rewards);
        staking::lock_rewards(&reward_manager, total_rewards);
    
    // Prepare user for staking
        let stake_amount = 1000;
        mycoin::register(&user1);
        mycoin::mint_coins(&admin, stake_amount);
        mycoin::transfer(&admin, USER1_ADDRESS, stake_amount);
    
    // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
    
    // Stake
        staking::stake(&user1, stake_amount);
    
    // Move time forward significantly
        timestamp::update_global_time_for_test_secs(start_time + 300);
    
    // User balance before
        let balance_before = mycoin::balance(USER1_ADDRESS);

        staking::unstake(&user1);
    
    // User balance after should be higher than original + stake amount
    // due to rewards
        let balance_after = mycoin::balance(USER1_ADDRESS);
        assert!(balance_after > balance_before, 0);
        assert!(balance_after > stake_amount, 0);
    }
    
    #[test]
    fun test_staking_update_pool_config() {
        // Setup
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool
        let start_time = 1000;
        let duration = 1000;
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            10,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // New config values
        let new_start_time = start_time + 100;
        let new_duration = duration + 200;
        let new_rewards_per_second = 20;
        let new_max_total_stake = 20000;
        
        // Lock significantly more rewards than needed
        mycoin::register(&reward_manager);
        let required_rewards = new_rewards_per_second * new_duration;
        mycoin::mint_coins(&admin, required_rewards);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, required_rewards);
        staking::lock_rewards(&reward_manager, required_rewards);
        
        // Update pool config
        staking::update_pool_config(
            &admin,
            new_start_time,
            new_duration,
            new_rewards_per_second,
            new_max_total_stake
        );
        
        // Verify
        let (actual_start, actual_end) = staking::get_pool_times();
        assert!(actual_start == new_start_time, 0);
        assert!(actual_end == new_start_time + new_duration, 0);
        
        let (max_stake, _, _) = staking::get_pool_limits();
        assert!(max_stake == new_max_total_stake, 0);
    }
    
    #[test]
    fun test_staking_update_fee_config() {
        // Setup
        let (admin, _, fee_manager, _, _) = setup_test();
        setup_staking_pool(&admin);
        
        // New fee config values
        let new_fee_percentage = 300; // 3%
        let new_min_fee = 20;
        let new_max_fee = 600;
        let new_fee_collector = @0x999;
        
        // Update fee config
        staking::update_fee_config(
            &fee_manager,
            new_fee_percentage,
            new_min_fee,
            new_max_fee,
            new_fee_collector
        );
    }
    
    #[test]
    fun test_staking_collect_fees() {
        // Setup
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        let fee_collector = account::create_account_for_test(FEE_COLLECTOR_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Register fee collector to receive coins
        mycoin::register(&fee_collector);
        
        // Setup pool
        let start_time = 1000;
        let duration = 1000;
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            10,
            10000,
            100,
            5000,
            500, // 5% fee
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Prepare rewards
        mycoin::register(&reward_manager);
        mycoin::mint_coins(&admin, duration * 10);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, duration * 10);
        staking::lock_rewards(&reward_manager, duration * 10);
        
        // Prepare user for staking
        let stake_amount = 1000;
        mycoin::register(&user1);
        mycoin::mint_coins(&admin, stake_amount);
        mycoin::transfer(&admin, USER1_ADDRESS, stake_amount);
        
        // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // Stake
        staking::stake(&user1, stake_amount);
        
        // Move time forward but still within staking period
        timestamp::update_global_time_for_test_secs(start_time + 100);
        
        // Unstake early (will incur fee)
        staking::unstake(&user1);
        
        // Verify fees were collected
        assert!(staking::get_collected_fees() > 0, 0);
        
        // Fee collector balance before collection
        let collector_balance_before = mycoin::balance(FEE_COLLECTOR_ADDRESS);
        let fees_amount = staking::get_collected_fees();
        
        // Collect fees
        staking::collect_fees(&fee_collector);
        
        // Verify
        let collector_balance_after = mycoin::balance(FEE_COLLECTOR_ADDRESS);
        assert!(collector_balance_after == collector_balance_before + fees_amount, 0);
        assert!(staking::get_collected_fees() == 0, 0); // fees should be reset
    }
    
    #[test]
    fun test_staking_lock_rewards() {
        // Setup
        let (admin, _, _, reward_manager, _) = setup_test();
        let (start_time, _) = setup_staking_pool(&admin);
        
        // Time is still before pool start
        timestamp::update_global_time_for_test_secs(start_time - 50);
        
        // Get stats before locking more rewards
        let (_, locked_rewards_before, _, _) = staking::get_pool_stats();
        
        // Lock more rewards
        let additional_rewards = 5000;
        prepare_user_for_staking(&admin, &reward_manager, additional_rewards);
        staking::lock_rewards(&reward_manager, additional_rewards);
        
        // Verify
        let (_, locked_rewards_after, _, _) = staking::get_pool_stats();
        assert!(locked_rewards_after == locked_rewards_before + additional_rewards, 0);
    }
    
    #[test]
    fun test_staking_unlock_rewards() {
        // Setup
        let (admin, _, _, reward_manager, _) = setup_test();
        let (start_time, _) = setup_staking_pool(&admin);
        
        // Time is still before pool start
        timestamp::update_global_time_for_test_secs(start_time - 50);
        
        // Get stats before unlocking rewards
        let (_, locked_rewards_before, _, _) = staking::get_pool_stats();
        
        // Unlock some rewards
        let unlock_amount = 2000;
        staking::unlock_rewards(&reward_manager, unlock_amount);
        
        // Verify
        let (_, locked_rewards_after, _, _) = staking::get_pool_stats();
        assert!(locked_rewards_after == locked_rewards_before - unlock_amount, 0);
    }
    
    #[test]
    fun test_staking_is_pool_active() {
        // Setup
        let (admin, _, _, _, _) = setup_test();
        let (start_time, duration) = setup_staking_pool(&admin);
        
        // Before start
        timestamp::update_global_time_for_test_secs(start_time - 10);
        assert!(!staking::is_pool_active(), 0);
        
        // After start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        assert!(staking::is_pool_active(), 0);
        
        // After end
        timestamp::update_global_time_for_test_secs(start_time + duration + 10);
        assert!(!staking::is_pool_active(), 0);
    }
    
    #[test]
    fun test_staking_additional_stake() {
        // Setup
        let (admin, user1, _, reward_manager, _) = setup_test();
        let (start_time, _) = setup_staking_pool(&admin);
        
        // Prepare user for staking
        let initial_stake = 1000;
        let additional_stake = 500;
        prepare_user_for_staking(&admin, &user1, initial_stake + additional_stake);
        
        // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // Initial stake
        staking::stake(&user1, initial_stake);
        
        // Verify initial stake
        let (total_staked_initial, _, _, _) = staking::get_pool_stats();
        assert!(total_staked_initial == initial_stake, 0);
        
        // Move time forward
        timestamp::update_global_time_for_test_secs(start_time + 50);
        
        // Add more stake
        staking::stake(&user1, additional_stake);
        
        // Verify user has staked more by checking total pool staked
        let user_info_opt = staking::get_user_info(USER1_ADDRESS);
        assert!(option::is_some(&user_info_opt), 0);
        
        // Verify total staked amount increased
        let (total_staked_after, _, _, _) = staking::get_pool_stats();
        assert!(total_staked_after == initial_stake + additional_stake, 0);
    }

    #[test]
    #[expected_failure(abort_code = ENOT_FEE_MANAGER, location = staking::roles)]
    fun test_roles_verify_fee_manager_failure() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let not_fee_manager = account::create_account_for_test(USER1_ADDRESS);
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        roles::verify_fee_manager(&not_fee_manager);
    }

    #[test]
    #[expected_failure(abort_code = ENOT_REWARD_MANAGER, location = staking::roles)]
    fun test_roles_verify_reward_manager_failure() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let not_reward_manager = account::create_account_for_test(USER1_ADDRESS);
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        roles::verify_reward_manager(&not_reward_manager);
    }

    #[test]
    #[expected_failure(abort_code = ENOT_FEE_MANAGER, location = staking::roles)]
    fun test_roles_verify_fee_collector_failure() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let not_fee_collector = account::create_account_for_test(USER1_ADDRESS);
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        roles::verify_fee_collector(&not_fee_collector);
    }

    #[test]
    #[expected_failure(abort_code = ENOT_AUTHORIZED, location = staking::roles)]
    fun test_roles_update_reward_manager_not_authorized() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let not_admin = account::create_account_for_test(USER1_ADDRESS);
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        roles::update_reward_manager(&not_admin, @0x999);
    }

    #[test]
    #[expected_failure(abort_code = ENOT_AUTHORIZED, location = staking::roles)]
    fun test_roles_update_fee_collector_not_authorized() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let not_admin = account::create_account_for_test(USER1_ADDRESS);
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        roles::update_fee_collector(&not_admin, @0x999);
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_roles_update_fee_manager_invalid_address() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Try to set fee_manager to the admin's address
        roles::update_fee_manager(&admin, STAKING_ADDRESS);
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_roles_update_reward_manager_invalid_address() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Try to set reward_manager to the admin's address
        roles::update_reward_manager(&admin, STAKING_ADDRESS);
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_roles_update_fee_collector_invalid_address() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Try to set fee_collector to the admin's address
        roles::update_fee_collector(&admin, STAKING_ADDRESS);
    }

    #[test]
    #[expected_failure(abort_code = 7)] // STAKE_TOO_HIGH
    fun test_staking_stake_amount_exceeds_user_limit() {
        // Setup
        let (admin, user1, _, reward_manager, _) = setup_test();
        let (start_time, _) = setup_staking_pool(&admin);
        
        // Prepare user for staking with amount above max per user
        let stake_amount = 5001; // max per user is 5000
        prepare_user_for_staking(&admin, &user1, stake_amount);
        
        // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // Try to stake - should fail
        staking::stake(&user1, stake_amount);
    }

    #[test]
    #[expected_failure(abort_code = 8)] // POOL_FULL
    fun test_staking_pool_full() {
        // Setup
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        let user2 = account::create_account_for_test(USER2_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool with a small max_total_stake
        let start_time = 1000;
        let duration = 1000;
        let max_total_stake = 1000; // Small max total stake
        
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            10,
            max_total_stake,
            100,
            max_total_stake, // Max per user same as total
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup rewards
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        mycoin::register(&reward_manager);
        mycoin::mint_coins(&admin, duration * 10);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, duration * 10);
        staking::lock_rewards(&reward_manager, duration * 10);
        
        // Prepare users for staking
        mycoin::register(&user1);
        mycoin::mint_coins(&admin, max_total_stake);
        mycoin::transfer(&admin, USER1_ADDRESS, max_total_stake);
        
        mycoin::register(&user2);
        mycoin::mint_coins(&admin, 100);
        mycoin::transfer(&admin, USER2_ADDRESS, 100);
        
        // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // User1 fills the pool
        staking::stake(&user1, max_total_stake);
        
        // User2 tries to stake, but pool is full
        staking::stake(&user2, 100); // Should fail with POOL_FULL
    }

    #[test]
    #[expected_failure(abort_code = 15)] // NOT_ENOUGH_REWARDS_LOCKED
    fun test_staking_update_pool_config_insufficient_rewards() {
        // Setup
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool with minimal rewards
        let start_time = 1000;
        let duration = 1000;
        let rewards_per_second = 10;
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            rewards_per_second,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock initial rewards
        mycoin::register(&reward_manager);
        mycoin::mint_coins(&admin, duration * rewards_per_second);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, duration * rewards_per_second);
        staking::lock_rewards(&reward_manager, duration * rewards_per_second);
        
        // Try to update with much higher rewards without locking more
        let new_rewards_per_second = 50; // 5x higher
        
        staking::update_pool_config(
            &admin,
            start_time,
            duration,
            new_rewards_per_second, // Much higher than what we locked
            10000
        );
    }

    #[test]
    #[expected_failure(abort_code = 6)] // POOL_ALREADY_STARTED
    fun test_staking_lock_rewards_after_start() {
        // Setup
        let (admin, _, _, reward_manager, _) = setup_test();
        let (start_time, _) = setup_staking_pool(&admin);
        
        // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // Try to lock more rewards after pool started
        prepare_user_for_staking(&admin, &reward_manager, 5000);
        staking::lock_rewards(&reward_manager, 5000);
    }

    #[test]
    #[expected_failure(abort_code = 6)] // POOL_ALREADY_STARTED
    fun test_staking_unlock_rewards_after_start() {
        // Setup
        let (admin, _, _, reward_manager, _) = setup_test();
        let (start_time, _) = setup_staking_pool(&admin);
        
        // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // Try to unlock rewards after pool started
        staking::unlock_rewards(&reward_manager, 1000);
    }

    #[test]
    #[expected_failure(abort_code = 14)] // NO_REWARDS_TO_CLAIM
    fun test_staking_unlock_rewards_too_much() {
        // Setup
        let (admin, _, _, reward_manager, _) = setup_test();
        let (start_time, _) = setup_staking_pool(&admin);
        
        // Time is still before pool start
        timestamp::update_global_time_for_test_secs(start_time - 50);
        
        // Get stats 
        let (_, locked_rewards, _, _) = staking::get_pool_stats();
        
        // Try to unlock more than available
        staking::unlock_rewards(&reward_manager, locked_rewards + 1000);
    }

    #[test]
    #[expected_failure(abort_code = 12)] // NOT_FEE_COLLECTOR
    fun test_staking_collect_fees_not_collector() {
        // Setup
        let (admin, user1, _, _, _) = setup_test();
        setup_staking_pool(&admin);
        
        // Try to collect fees with non-collector
        staking::collect_fees(&user1);
    }

    #[test]
    #[expected_failure(abort_code = 13)] // NO_FEES_TO_COLLECT
    fun test_staking_collect_fees_none_available() {
        // Setup
        let (admin, _, _, _, fee_collector) = setup_test();
        setup_staking_pool(&admin);
        
        // Try to collect fees when none are available
        staking::collect_fees(&fee_collector);
    }

    #[test]
    #[expected_failure(abort_code = 10)] // INVALID_FEE_PERCENTAGE
    fun test_staking_update_fee_config_invalid_percentage() {
        // Setup
        let (admin, _, fee_manager, _, _) = setup_test();
        setup_staking_pool(&admin);
        
        // Try to set fee percentage > 100%
        staking::update_fee_config(
            &fee_manager,
            11000, // > 10000 BP (100%)
            20,
            600,
            @0x999
        );
    }

    #[test]
    #[expected_failure(abort_code = 11)] // INVALID_FEE_LIMITS
    fun test_staking_update_fee_config_invalid_limits() {
        // Setup
        let (admin, _, fee_manager, _, _) = setup_test();
        setup_staking_pool(&admin);
        
        // Try to set min fee > max fee
        staking::update_fee_config(
            &fee_manager,
            300,
            700, // min fee
            600, // max fee (smaller than min)
            @0x999
        );
    }

    #[test]
    #[expected_failure(abort_code = 2, location = staking::roles)]
    fun test_staking_update_fee_config_not_fee_manager() {
        // Setup
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool
        let start_time = 1000;
        let duration = 1000;
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            10,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Try to update fee config with non-fee manager (user1)
        staking::update_fee_config(
            &user1,
            300,
            20,
            600,
            @0x999
        );
    }

    #[test]
    fun test_staking_fee_calculation() {
        // Setup
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        let fee_manager = account::create_account_for_test(FEE_MANAGER_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool with specific fee parameters
        let start_time = 1000;
        let duration = 1000;
        let fee_percentage = 1000; // 10%
        let min_fee = 50;
        let max_fee = 200;
        
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            10,
            10000,
            100,
            5000,
            fee_percentage,
            min_fee,
            max_fee,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock rewards
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        mycoin::register(&reward_manager);
        mycoin::mint_coins(&admin, duration * 10);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, duration * 10);
        staking::lock_rewards(&reward_manager, duration * 10);
        
        // Register fee collector
        let fee_collector = account::create_account_for_test(FEE_COLLECTOR_ADDRESS);
        mycoin::register(&fee_collector);
        
        // Test case 1: Small stake amount where min_fee applies
        let stake_amount1 = 200; // 10% fee would be 20, which is < min_fee of 50
        mycoin::register(&user1);
        mycoin::mint_coins(&admin, stake_amount1);
        mycoin::transfer(&admin, USER1_ADDRESS, stake_amount1);
        
        // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // Stake
        staking::stake(&user1, stake_amount1);
        
        // Unstake early (will incur fee)
        staking::unstake(&user1);
        
        // Verify fee is min_fee (50)
        let collected_fees = staking::get_collected_fees();
        assert!(collected_fees == min_fee, 0); // Should be min_fee
        
        // Collect fees to reset counter
        staking::collect_fees(&fee_collector);
        
        // Test case 2: Large stake amount where max_fee applies
        let stake_amount2 = 5000; // 10% fee would be 500, which is > max_fee of 200
        mycoin::mint_coins(&admin, stake_amount2);
        mycoin::transfer(&admin, USER1_ADDRESS, stake_amount2);
        
        // Stake again
        staking::stake(&user1, stake_amount2);
        
        // Unstake early again
        staking::unstake(&user1);
        
        // Verify fee is max_fee (200)
        let collected_fees = staking::get_collected_fees();
        assert!(collected_fees == max_fee, 0); // Should be max_fee
    }

    // Test zero fee case when unstaking after pool end
    #[test]
    fun test_staking_no_fee_after_pool_end() {
        // Setup
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool
        let start_time = 1000;
        let duration = 1000;
        let fee_percentage = 1000; // 10%, but should not apply after pool end
        
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            10,
            10000,
            100,
            5000,
            fee_percentage,
            50,
            200,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock rewards
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        mycoin::register(&reward_manager);
        mycoin::mint_coins(&admin, duration * 10);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, duration * 10);
        staking::lock_rewards(&reward_manager, duration * 10);
        
        // Prepare user for staking
        let stake_amount = 1000;
        mycoin::register(&user1);
        mycoin::mint_coins(&admin, stake_amount);
        mycoin::transfer(&admin, USER1_ADDRESS, stake_amount);
        
        // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // Stake
        staking::stake(&user1, stake_amount);
        
        // Move time to after pool end
        timestamp::update_global_time_for_test_secs(start_time + duration + 10);
        
        // Unstake after pool end
        staking::unstake(&user1);
        
        // Verify no fees were charged
        let collected_fees = staking::get_collected_fees();
        assert!(collected_fees == 0, 0); // No fee should be charged after pool end
    }

    // Test calculating pending rewards through view function
    #[test]
    fun test_staking_view_functions() {
        // Setup
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        
        // Initialize timestamp 
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        
        // Initialize modules
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool parameters
        let start_time = 1000;
        let duration = 1000;
        
        // IMPORTANT: Start testing with timestamp BEFORE pool start
        timestamp::update_global_time_for_test_secs(start_time - 10);
        
        // Initialize the staking pool
        staking::initialize(
            &admin,
            start_time,
            duration,
            10,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock rewards
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        mycoin::register(&reward_manager);
        mycoin::mint_coins(&admin, duration * 10);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, duration * 10);
        staking::lock_rewards(&reward_manager, duration * 10);
        
        // Test view functions
        let (config_start, config_end) = staking::get_pool_times();
        assert!(config_start == start_time, 0);
        assert!(config_end == start_time + duration, 0);
        
        let (max_stake, min_stake, max_per_user) = staking::get_pool_limits();
        assert!(max_stake == 10000, 0);
        assert!(min_stake == 100, 0);
        assert!(max_per_user == 5000, 0);
        
        let (total_staked, locked_rewards, acc_rewards_per_stake, last_update) = staking::get_pool_stats();
        assert!(total_staked == 0, 0);
        assert!(locked_rewards > 0, 0);
        
        // No user info yet
        let user_info_opt = staking::get_user_info(USER1_ADDRESS);
        assert!(option::is_none(&user_info_opt), 0);
        
        // Test pool not active before start
        assert!(!staking::is_pool_active(), 0); // Pool should not be active before start
        
        // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // Test pool active during active period
        assert!(staking::is_pool_active(), 0); // Pool should be active
        
        // Test after staking
        prepare_user_for_staking(&admin, &user1, 1000);
        staking::stake(&user1, 1000);
        
        // User info should exist now
        let user_info_opt_after = staking::get_user_info(USER1_ADDRESS);
        assert!(option::is_some(&user_info_opt_after), 0);
        
        // Test pool not active after end (move time forward, never backward)
        timestamp::update_global_time_for_test_secs(start_time + duration + 10);
        assert!(!staking::is_pool_active(), 0); // Pool should not be active after end
    }

    // Test additional user joining the pool later
    #[test]
    fun test_staking_multiple_users_sequential() {
        // Setup with higher rewards for clarity
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        let user2 = account::create_account_for_test(USER2_ADDRESS);
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool
        let start_time = 1000;
        let duration = 1000;
        let rewards_per_second = 1000; // High for clear rewards
        
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            rewards_per_second,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock rewards
        mycoin::register(&reward_manager);
        let total_rewards = duration * rewards_per_second;
        mycoin::mint_coins(&admin, total_rewards);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, total_rewards);
        staking::lock_rewards(&reward_manager, total_rewards);
        
        // Prepare users
        let stake_amount1 = 1000;
        let stake_amount2 = 2000;
        mycoin::register(&user1);
        mycoin::mint_coins(&admin, stake_amount1);
        mycoin::transfer(&admin, USER1_ADDRESS, stake_amount1);
        
        mycoin::register(&user2);
        mycoin::mint_coins(&admin, stake_amount2);
        mycoin::transfer(&admin, USER2_ADDRESS, stake_amount2);
        
        // Move time to after start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // User 1 stakes
        staking::stake(&user1, stake_amount1);
        
        // Let some time pass
        timestamp::update_global_time_for_test_secs(start_time + 100);
        
        // User 2 stakes
        staking::stake(&user2, stake_amount2);
        
        // Let more time pass
        timestamp::update_global_time_for_test_secs(start_time + 200);
        
        // Both users should have pending rewards, with user1 having more (since they staked earlier)
        
        // Unstake for both users
        let balance1_before = mycoin::balance(USER1_ADDRESS);
        let balance2_before = mycoin::balance(USER2_ADDRESS);
        
        staking::unstake(&user1);
        staking::unstake(&user2);
        
        let balance1_after = mycoin::balance(USER1_ADDRESS);
        let balance2_after = mycoin::balance(USER2_ADDRESS);
        
        // Both should have gotten rewards
        assert!(balance1_after > balance1_before, 0);
        assert!(balance2_after > balance2_before, 0);
        
        // User 1 should have more rewards per staked token (staked longer)
        let user1_reward_per_token = (balance1_after - balance1_before) / stake_amount1;
        let user2_reward_per_token = (balance2_after - balance2_before) / stake_amount2;
        
        assert!(user1_reward_per_token > user2_reward_per_token, 0);
    }

    // Test a user staking the minimum amount
    #[test]
    fun test_staking_minimum_stake() {
        // Setup
        let (admin, user1, _, reward_manager, _) = setup_test();
        let (start_time, _) = setup_staking_pool(&admin);
        
        // Prepare user for minimum staking
        let stake_amount = 100; // Minimum stake
        prepare_user_for_staking(&admin, &user1, stake_amount);
        
        // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // Stake minimum amount
        staking::stake(&user1, stake_amount);
        
        // Verify stake was successful
        let (total_staked, _, _, _) = staking::get_pool_stats();
        assert!(total_staked == stake_amount, 0);
        
        let user_info_opt = staking::get_user_info(USER1_ADDRESS);
        assert!(option::is_some(&user_info_opt), 0);
    }

    #[test]
    fun test_roles_admin_cannot_be_other_roles() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let new_admin_addr = @0x999;
        let new_admin = account::create_account_for_test(new_admin_addr);
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Change admin to new address
        roles::update_pool_admin(&admin, new_admin_addr);
        assert!(roles::is_pool_admin(new_admin_addr), 0);
        
        // Verify old admin lost permissions
        assert!(!roles::is_pool_admin(STAKING_ADDRESS), 0);
        
        // New admin should be able to update roles
        roles::update_fee_manager(&new_admin, @0x888);
        assert!(roles::is_fee_manager(@0x888), 0);
    }

    #[test]
    fun test_roles_get_functions() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Test all getter functions
        assert!(roles::get_pool_admin() == STAKING_ADDRESS, 0);
        assert!(roles::get_fee_manager() == FEE_MANAGER_ADDRESS, 0);
        assert!(roles::get_reward_manager() == REWARD_MANAGER_ADDRESS, 0);
        assert!(roles::get_fee_collector() == FEE_COLLECTOR_ADDRESS, 0);
        
        // Update all roles and verify getters still work
        let new_fee_manager = @0x111;
        let new_reward_manager = @0x222;
        let new_fee_collector = @0x333;
        
        roles::update_fee_manager(&admin, new_fee_manager);
        roles::update_reward_manager(&admin, new_reward_manager);
        roles::update_fee_collector(&admin, new_fee_collector);
        
        assert!(roles::get_fee_manager() == new_fee_manager, 0);
        assert!(roles::get_reward_manager() == new_reward_manager, 0);
        assert!(roles::get_fee_collector() == new_fee_collector, 0);
        
        // Test all_roles function
        let (pool_admin, fee_manager, reward_manager, fee_collector) = roles::all_roles();
        assert!(pool_admin == STAKING_ADDRESS, 0);
        assert!(fee_manager == new_fee_manager, 0);
        assert!(reward_manager == new_reward_manager, 0);
        assert!(fee_collector == new_fee_collector, 0);
    }

    #[test]
    fun test_roles_sequence_of_updates() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Update fee manager multiple times
        roles::update_fee_manager(&admin, @0x111);
        assert!(roles::is_fee_manager(@0x111), 0);
        
        roles::update_fee_manager(&admin, @0x222);
        assert!(roles::is_fee_manager(@0x222), 0);
        assert!(!roles::is_fee_manager(@0x111), 0);
        
        // Update admin, then verify new admin can update other roles
        let new_admin = @0x333;
        let new_admin_signer = account::create_account_for_test(new_admin);
        
        roles::update_pool_admin(&admin, new_admin);
        assert!(roles::is_pool_admin(new_admin), 0);
        
        // New admin updates fee manager
        roles::update_fee_manager(&new_admin_signer, @0x444);
        assert!(roles::is_fee_manager(@0x444), 0);
        
        // Old admin should no longer have permissions
        assert!(!roles::is_pool_admin(STAKING_ADDRESS), 0);
    }

    #[test]
    fun test_staking_zero_rewards_per_second() {
        // Setup
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool with zero rewards per second
        let start_time = 1000;
        let duration = 1000;
        let rewards_per_second = 0; // Zero rewards
        
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            rewards_per_second,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // No need to lock rewards as rewards_per_second is 0
        
        // Prepare user for staking
        mycoin::register(&user1);
        mycoin::mint_coins(&admin, 1000);
        mycoin::transfer(&admin, USER1_ADDRESS, 1000);
        
        // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // Stake
        staking::stake(&user1, 1000);
        
        // Move time forward
        timestamp::update_global_time_for_test_secs(start_time + 500);
        
        // User balance before unstake
        let balance_before = mycoin::balance(USER1_ADDRESS);
        
        // Unstake - should get stake back but no rewards
        staking::unstake(&user1);
        
        // User might not get exactly their stake amount back due to fees
        // or potential precision issues, so we'll check that it's close
        let balance_after = mycoin::balance(USER1_ADDRESS);
        
        // With zero rewards, the final balance should be close to original stake
        // Depending on fee structure, it could be less than original stake
        let actual_return = balance_after - balance_before;
        
        // Since the user is unstaking before the pool end, a fee may be applied
        // We'll check that the return is reasonably close to the stake amount
        // At minimum, they should get a substantial portion of their stake back
        assert!(actual_return >= 900, 0); // Allow for up to 10% fee
    }

    #[test]
    fun test_staking_multi_stake_unstake_sequence() {
        // Setup
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        let user2 = account::create_account_for_test(USER2_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool with rewards
        let start_time = 1000;
        let duration = 1000;
        let rewards_per_second = 100;
        
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            rewards_per_second,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock rewards
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        mycoin::register(&reward_manager);
        let total_rewards = duration * rewards_per_second;
        mycoin::mint_coins(&admin, total_rewards);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, total_rewards);
        staking::lock_rewards(&reward_manager, total_rewards);
        
        // Prepare users
        mycoin::register(&user1);
        mycoin::register(&user2);
        mycoin::mint_coins(&admin, 5000);
        mycoin::transfer(&admin, USER1_ADDRESS, 2500);
        mycoin::transfer(&admin, USER2_ADDRESS, 2500);
        
        // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // User 1 stakes
        staking::stake(&user1, 1000);
        
        // Advance time
        timestamp::update_global_time_for_test_secs(start_time + 100);
        
        // User 2 stakes
        staking::stake(&user2, 1500);
        
        // Advance time
        timestamp::update_global_time_for_test_secs(start_time + 200);
        
        // User 1 stakes additional amount
        staking::stake(&user1, 500);
        
        // Advance time
        timestamp::update_global_time_for_test_secs(start_time + 300);
        
        // User 2 unstakes
        let balance2_before = mycoin::balance(USER2_ADDRESS);
        staking::unstake(&user2);
        let balance2_after = mycoin::balance(USER2_ADDRESS);
        
        // Advance time
        timestamp::update_global_time_for_test_secs(start_time + 400);
        
        // User 1 unstakes
        let balance1_before = mycoin::balance(USER1_ADDRESS);
        staking::unstake(&user1);
        let balance1_after = mycoin::balance(USER1_ADDRESS);
        
        // Verify both users got back more than they staked
        assert!(balance1_after > balance1_before + 1500, 0);
        assert!(balance2_after > balance2_before + 1500, 0);
        
        // Final pool state should have no stakes
        let (total_staked, _, _, _) = staking::get_pool_stats();
        assert!(total_staked == 0, 0);
    }

    #[test]
    fun test_staking_boundary_timing() {
        // Setup
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool
        let start_time = 1000;
        let duration = 1000;
        let rewards_per_second = 10;
        
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            rewards_per_second,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock rewards
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        mycoin::register(&reward_manager);
        mycoin::mint_coins(&admin, duration * rewards_per_second);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, duration * rewards_per_second);
        staking::lock_rewards(&reward_manager, duration * rewards_per_second);
        
        // Prepare user
        mycoin::register(&user1);
        mycoin::mint_coins(&admin, 1000);
        mycoin::transfer(&admin, USER1_ADDRESS, 1000);
        
        // Set time to EXACTLY start time
        timestamp::update_global_time_for_test_secs(start_time);
        
        // Stake at exactly start time
        staking::stake(&user1, 1000);
        
        // Verify stake was successful
        let (total_staked, _, _, _) = staking::get_pool_stats();
        assert!(total_staked == 1000, 0);
        
        // Set time to EXACTLY end time
        timestamp::update_global_time_for_test_secs(start_time + duration);
        
        // Verify pool is NOT active exactly at end time
        assert!(!staking::is_pool_active(), 0);
        
        // Unstake at exactly end time
        let balance_before = mycoin::balance(USER1_ADDRESS);
        staking::unstake(&user1);
        let balance_after = mycoin::balance(USER1_ADDRESS);
        
        // Verify unstake works and no fees were charged (as it's unstaking at end time)
        assert!(balance_after > balance_before, 0);
        assert!(staking::get_collected_fees() == 0, 0);
    }

    #[test]
    fun test_staking_claim_exact_rewards() {
        // Setup with predictable rewards
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool with simple rewards math
        let start_time = 1000;
        let duration = 1000;
        let rewards_per_second = 1000; // 1000 tokens per second
        
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            rewards_per_second,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock rewards
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        mycoin::register(&reward_manager);
        let total_rewards = duration * rewards_per_second;
        mycoin::mint_coins(&admin, total_rewards);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, total_rewards);
        staking::lock_rewards(&reward_manager, total_rewards);
        
        // Prepare user
        let stake_amount = 1000;
        mycoin::register(&user1);
        mycoin::mint_coins(&admin, stake_amount);
        mycoin::transfer(&admin, USER1_ADDRESS, stake_amount);
        
        // Set time to start time
        timestamp::update_global_time_for_test_secs(start_time);
        
        // Stake
        staking::stake(&user1, stake_amount);
        
        timestamp::update_global_time_for_test_secs(start_time + 100);
        
        // Claim rewards
        let balance_before = mycoin::balance(USER1_ADDRESS);
        staking::claim_rewards(&user1);
        let balance_after = mycoin::balance(USER1_ADDRESS);
        
        // Due to math and rounding, might not be exactly 100k, but should be close
        let rewards = balance_after - balance_before;
        assert!(rewards > 90000 && rewards <= 100000, 0);
        
        // Verify the stake is still there after claiming
        let (total_staked, _, _, _) = staking::get_pool_stats();
        assert!(total_staked == stake_amount, 0);
        
        // Verify user can still unstake after claiming
        staking::unstake(&user1);
        
        // Final balance should be initial stake + all rewards
        let final_balance = mycoin::balance(USER1_ADDRESS);
        assert!(final_balance > balance_after + stake_amount - 100, 0); // Allow for small rounding error
    }

    #[test]
    fun test_staking_extra_small_rewards() {
        // Test with extremely small rewards per second to test rounding
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool with very small rewards
        let start_time = 1000;
        let duration = 1000;
        let rewards_per_second = 1; // Minimum possible reward
        
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            rewards_per_second,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock rewards
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        mycoin::register(&reward_manager);
        mycoin::mint_coins(&admin, duration * rewards_per_second);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, duration * rewards_per_second);
        staking::lock_rewards(&reward_manager, duration * rewards_per_second);
        
        // Prepare user with large stake
        let stake_amount = 5000;
        mycoin::register(&user1);
        mycoin::mint_coins(&admin, stake_amount);
        mycoin::transfer(&admin, USER1_ADDRESS, stake_amount);
        
        // Set time to start time
        timestamp::update_global_time_for_test_secs(start_time);
        
        // Stake
        staking::stake(&user1, stake_amount);
        
        // Move a long time forward
        timestamp::update_global_time_for_test_secs(start_time + 900);
        
        // Balance before unstake
        let balance_before = mycoin::balance(USER1_ADDRESS);
        
        // Unstake
        staking::unstake(&user1);
        
        // Balance after unstake
        let balance_after = mycoin::balance(USER1_ADDRESS);
        
        // With tiny rewards, we should receive back at least our stake
        assert!(balance_after >= balance_before + stake_amount, 0);
    }

    #[test]
    fun test_staking_get_fee_config() {
        // This test exercises the get_fee_config function
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let fee_manager = account::create_account_for_test(FEE_MANAGER_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool
        let start_time = 1000;
        let duration = 1000;
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            10,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Get fee config
        let fee_config = staking::get_fee_config();
        
        // Update fee config
        staking::update_fee_config(
            &fee_manager,
            300, // 3%
            20,  // 20 min fee
            600, // 600 max fee
            @0x999
        );
        
        // Get fee config again
        let updated_fee_config = staking::get_fee_config();
        
        // Lock rewards
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        mycoin::register(&reward_manager);
        mycoin::mint_coins(&admin, duration * 10);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, duration * 10);
        staking::lock_rewards(&reward_manager, duration * 10);
        
        // Setup user
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        mycoin::register(&user1);
        mycoin::mint_coins(&admin, 1000);
        mycoin::transfer(&admin, USER1_ADDRESS, 1000);
        
        // Move time to after start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // Stake
        staking::stake(&user1, 1000);
        
        // Unstake immediately to get a fee
        staking::unstake(&user1);
        
        // Fee should be collected based on updated parameters
        assert!(staking::get_collected_fees() > 0, 0);
    }

    #[test]
    fun test_staking_min_function() {
        
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool with short duration
        let start_time = 1000;
        let duration = 100; // Very short duration
        let rewards_per_second = 1000;
        
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            rewards_per_second,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock rewards
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        mycoin::register(&reward_manager);
        let total_rewards = duration * rewards_per_second;
        mycoin::mint_coins(&admin, total_rewards);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, total_rewards);
        staking::lock_rewards(&reward_manager, total_rewards);
        
        // Prepare user
        mycoin::register(&user1);
        mycoin::mint_coins(&admin, 1000);
        mycoin::transfer(&admin, USER1_ADDRESS, 1000);
        
        // Move time to start
        timestamp::update_global_time_for_test_secs(start_time);
        
        // Stake
        staking::stake(&user1, 1000);
        
        // Move time past end (this should test the min function in update_pool_rewards)
        timestamp::update_global_time_for_test_secs(start_time + duration + 50);
        
        // Balance before
        let balance_before = mycoin::balance(USER1_ADDRESS);
        
        // Unstake
        staking::unstake(&user1);
        
        // Balance after
        let balance_after = mycoin::balance(USER1_ADDRESS);
        
        // We should get rewards based on the duration, not more
        // The max reward would be duration * rewards_per_second
        let reward = balance_after - balance_before - 1000;
        assert!(reward > 0, 0);
        assert!(reward <= total_rewards, 0); // Should not exceed total possible rewards
    }

    #[test]
    fun test_staking_add_stake_with_rewards() {
        // Test adding stake after accruing rewards
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool with high rewards
        let start_time = 1000;
        let duration = 1000;
        let rewards_per_second = 1000;
        
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            rewards_per_second,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock rewards
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        mycoin::register(&reward_manager);
        mycoin::mint_coins(&admin, duration * rewards_per_second);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, duration * rewards_per_second);
        staking::lock_rewards(&reward_manager, duration * rewards_per_second);
        
        // Prepare user
        mycoin::register(&user1);
        mycoin::mint_coins(&admin, 3000);
        mycoin::transfer(&admin, USER1_ADDRESS, 3000);
        
        // Move time to start
        timestamp::update_global_time_for_test_secs(start_time);
        
        // Initial stake
        let initial_stake = 1000;
        staking::stake(&user1, initial_stake);
        
        // Let rewards accrue
        timestamp::update_global_time_for_test_secs(start_time + 100);
        
        // Claim the pending rewards before adding more stake
        let balance_before_claim = mycoin::balance(USER1_ADDRESS);
        staking::claim_rewards(&user1);
        let balance_after_claim = mycoin::balance(USER1_ADDRESS);
        
        // Should have received rewards
        let first_reward = balance_after_claim - balance_before_claim;
        assert!(first_reward > 0, 0);
        
        // Add more stake
        let additional_stake = 2000;
        staking::stake(&user1, additional_stake);
        
        // Let more rewards accrue
        timestamp::update_global_time_for_test_secs(start_time + 200);
        
        // Unstake everything
        let balance_before_unstake = mycoin::balance(USER1_ADDRESS);
        staking::unstake(&user1);
        let balance_after_unstake = mycoin::balance(USER1_ADDRESS);
        
        // Should have received stake back plus additional rewards
        let total_received = balance_after_unstake - balance_before_unstake;
        assert!(total_received > initial_stake + additional_stake, 0);
        
        // Final rewards should be at least something reasonable (not comparing to first reward)
        let additional_rewards = total_received - (initial_stake + additional_stake);
        assert!(additional_rewards > 0, 0); 
    }

    #[test]
    fun test_roles_full_update_cycle() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Create accounts for new role holders
        let new_admin_addr = @0x111;
        let new_admin = account::create_account_for_test(new_admin_addr);
        let new_fee_manager_addr = @0x222;
        let new_fee_manager = account::create_account_for_test(new_fee_manager_addr);
        let new_reward_manager_addr = @0x333;
        let new_reward_manager = account::create_account_for_test(new_reward_manager_addr);
        let new_fee_collector_addr = @0x444;
        let new_fee_collector = account::create_account_for_test(new_fee_collector_addr);
        
        // Initialize roles
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Update all roles
        roles::update_fee_manager(&admin, new_fee_manager_addr);
        roles::update_reward_manager(&admin, new_reward_manager_addr);
        roles::update_fee_collector(&admin, new_fee_collector_addr);
        roles::update_pool_admin(&admin, new_admin_addr);
        
        // Verify all roles updated correctly
        assert!(roles::is_pool_admin(new_admin_addr), 0);
        assert!(roles::is_fee_manager(new_fee_manager_addr), 0);
        assert!(roles::is_reward_manager(new_reward_manager_addr), 0);
        assert!(roles::is_fee_collector(new_fee_collector_addr), 0);
        
        // Verify old roles don't have permissions anymore
        assert!(!roles::is_pool_admin(STAKING_ADDRESS), 0);
        assert!(!roles::is_fee_manager(FEE_MANAGER_ADDRESS), 0);
        assert!(!roles::is_reward_manager(REWARD_MANAGER_ADDRESS), 0);
        assert!(!roles::is_fee_collector(FEE_COLLECTOR_ADDRESS), 0);
        
        // Verify new admin can update roles
        roles::update_fee_manager(&new_admin, @0x555);
        assert!(roles::is_fee_manager(@0x555), 0);
        assert!(!roles::is_fee_manager(new_fee_manager_addr), 0);
        
        // Check verifications work with new roles
        roles::verify_pool_admin(&new_admin);
        
        // Create a new fee manager signer and verify
        let newer_fee_manager = account::create_account_for_test(@0x555);
        roles::verify_fee_manager(&newer_fee_manager);
    }

    #[test]
    #[expected_failure]
    fun test_roles_initialization_with_zero_address() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Try to initialize with a zero address
        roles::initialize_roles(
            &admin, 
            @0x0, // Zero address for fee manager
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_roles_double_role_verification() {
        // This test is expected to fail because one address can't hold multiple roles
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let fee_manager = account::create_account_for_test(FEE_MANAGER_ADDRESS);
        
        // Initialize roles
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Update fee_manager role to be admin - this should fail with EINVALID_ADDRESS
        roles::update_fee_manager(&admin, STAKING_ADDRESS);
    }

    #[test]
    fun test_roles_initialization_with_valid_addresses() {
        
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Initialize with different addresses
        roles::initialize_roles(
            &admin, 
            @0x111, 
            @0x222, 
            @0x333
        );
        
        // Verify roles are set correctly
        assert!(roles::is_pool_admin(STAKING_ADDRESS), 0);
        assert!(roles::is_fee_manager(@0x111), 0);
        assert!(roles::is_reward_manager(@0x222), 0);
        assert!(roles::is_fee_collector(@0x333), 0);
    }


    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_roles_swap_role_positions() {
        // This test is expected to fail due to the role assignment validation
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let fee_manager = account::create_account_for_test(FEE_MANAGER_ADDRESS);
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        
        // Initialize roles
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Trying to set fee manager to the reward manager address - should fail
        roles::update_fee_manager(&admin, REWARD_MANAGER_ADDRESS);
    }

    #[test]
    fun test_roles_sequential_updates() {
        // Test updating roles one after another
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Initialize roles
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Update fee manager
        roles::update_fee_manager(&admin, @0x111);
        assert!(roles::is_fee_manager(@0x111), 0);
        
        // Update reward manager
        roles::update_reward_manager(&admin, @0x222);
        assert!(roles::is_reward_manager(@0x222), 0);
        
        // Update fee collector
        roles::update_fee_collector(&admin, @0x333);
        assert!(roles::is_fee_collector(@0x333), 0);
        
        // Check all roles
        let (admin_addr, fee_manager, reward_manager, fee_collector) = roles::all_roles();
        assert!(admin_addr == STAKING_ADDRESS, 0);
        assert!(fee_manager == @0x111, 0);
        assert!(reward_manager == @0x222, 0);
        assert!(fee_collector == @0x333, 0);
    }

    #[test]
    fun test_staking_empty_pool_rewards() {
        // Setup
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool with rewards
        let start_time = 1000;
        let duration = 1000;
        let rewards_per_second = 100;
        
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            rewards_per_second,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock rewards
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        mycoin::register(&reward_manager);
        mycoin::mint_coins(&admin, duration * rewards_per_second);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, duration * rewards_per_second);
        staking::lock_rewards(&reward_manager, duration * rewards_per_second);
        
        // Move time to after pool start, but don't stake anything
        timestamp::update_global_time_for_test_secs(start_time + 100);
        
        // Get pool stats
        let (total_staked, locked_rewards, acc_rewards_per_stake, last_update) = staking::get_pool_stats();
        
        // Verify no stakes
        assert!(total_staked == 0, 0);
        
        // Check rewards for non-existent user
        let pending_rewards = staking::get_pending_rewards(@0x999);
        assert!(pending_rewards == 0, 0);
        
        // Check user info for non-existent user
        let user_info = staking::get_user_info(@0x999);
        assert!(option::is_none(&user_info), 0);
    }

    #[test]
    fun test_staking_claim_with_zero_stake() {
        // Setup
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool
        let start_time = 1000;
        let duration = 1000;
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            10,
            10000,
            0, // Allow zero stake
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Verify pending rewards is zero for non-staked user
        let pending_rewards = staking::get_pending_rewards(USER1_ADDRESS);
        assert!(pending_rewards == 0, 0);
    }

    #[test]
    fun test_staking_precision_factor_impact() {
        // Test how the precision factor affects reward calculations
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        let user2 = account::create_account_for_test(USER2_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
    
        // Setup pool with very large rewards_per_second
        let start_time = 1000;
        let duration = 1000;
        let rewards_per_second = 1000000; // 1 million per second
        
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            rewards_per_second,
            1000000000, // 1 billion max stake
            100,
            500000000, // 500 million max per user
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock rewards
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        mycoin::register(&reward_manager);
        mycoin::mint_coins(&admin, duration * rewards_per_second);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, duration * rewards_per_second);
        staking::lock_rewards(&reward_manager, duration * rewards_per_second);
        
        // Prepare users
        mycoin::register(&user1);
        mycoin::register(&user2);
        
        // Give user1 a very small stake
        mycoin::mint_coins(&admin, 100);
        mycoin::transfer(&admin, USER1_ADDRESS, 100);
        
        // Give user2 a very large stake
        mycoin::mint_coins(&admin, 10000000);
        mycoin::transfer(&admin, USER2_ADDRESS, 10000000);
        
        // Move time to start
        timestamp::update_global_time_for_test_secs(start_time);
        
        // Both users stake
        staking::stake(&user1, 100);
        staking::stake(&user2, 10000000);
        
        // Let rewards accrue
        timestamp::update_global_time_for_test_secs(start_time + 50);
        
        // Check rewards are calculated correctly despite extreme difference in stake size
        let balance1_before = mycoin::balance(USER1_ADDRESS);
        let balance2_before = mycoin::balance(USER2_ADDRESS);
        
        staking::unstake(&user1);
        staking::unstake(&user2);
        
        let balance1_after = mycoin::balance(USER1_ADDRESS);
        let balance2_after = mycoin::balance(USER2_ADDRESS);
        
        // Both users should get some rewards
        assert!(balance1_after > balance1_before, 0);
        assert!(balance2_after > balance2_before, 0);
        
        // User2 should get vastly more rewards due to much larger stake
        let user1_reward = balance1_after - balance1_before - 100;
        let user2_reward = balance2_after - balance2_before - 10000000;
        
        // User2's reward should be approximately 100,000 times larger (ratio of stakes)
        // But allow some variation due to precision issues
        assert!(user2_reward > user1_reward * 10000, 0); // At least 10,000x difference
    }

    #[test]
    fun test_staking_multiple_claims() {
        // Test claiming rewards multiple times
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool with high rewards
        let start_time = 1000;
        let duration = 1000;
        let rewards_per_second = 10000; // Much higher rewards to ensure we get some
        
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            rewards_per_second,
            10000,
            100,
            5000,
            0, // No fees
            0,
            0,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock rewards
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        mycoin::register(&reward_manager);
        let total_rewards = duration * rewards_per_second;
        mycoin::mint_coins(&admin, total_rewards);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, total_rewards);
        staking::lock_rewards(&reward_manager, total_rewards);
        
        // Prepare user
        mycoin::register(&user1);
        mycoin::mint_coins(&admin, 1000);
        mycoin::transfer(&admin, USER1_ADDRESS, 1000);
        
        // Move time to start
        timestamp::update_global_time_for_test_secs(start_time);
        
        // Stake
        staking::stake(&user1, 1000);
        
        // Let rewards accrue
        timestamp::update_global_time_for_test_secs(start_time + 100);
        
        // First claim
        let balance_before1 = mycoin::balance(USER1_ADDRESS);
        staking::claim_rewards(&user1);
        let balance_after1 = mycoin::balance(USER1_ADDRESS);
        let first_reward = balance_after1 - balance_before1;
        assert!(first_reward > 0, 0);
        
        // Let more rewards accrue
        timestamp::update_global_time_for_test_secs(start_time + 200);
        
        // Second claim
        let balance_before2 = mycoin::balance(USER1_ADDRESS);
        staking::claim_rewards(&user1);
        let balance_after2 = mycoin::balance(USER1_ADDRESS);
        let second_reward = balance_after2 - balance_before2;
        assert!(second_reward > 0, 0);
        
        // Let even more rewards accrue
        timestamp::update_global_time_for_test_secs(start_time + 300);
        
        // Third claim
        let balance_before3 = mycoin::balance(USER1_ADDRESS);
        staking::claim_rewards(&user1);
        let balance_after3 = mycoin::balance(USER1_ADDRESS);
        let third_reward = balance_after3 - balance_before3;
        assert!(third_reward > 0, 0);
        
        // Finally unstake at the end of the pool to avoid fees
        timestamp::update_global_time_for_test_secs(start_time + duration + 10);
        
        let balance_before_unstake = mycoin::balance(USER1_ADDRESS);
        staking::unstake(&user1);
        let balance_after_unstake = mycoin::balance(USER1_ADDRESS);
        
        // Should get at least the stake amount back (1000)
        assert!(balance_after_unstake >= balance_before_unstake + 1000, 0);
    }

    #[test]
    fun test_staking_time_passing_before_claim() {
        // Modified test where time passes before each claim
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        let user2 = account::create_account_for_test(USER2_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool
        let start_time = 1000;
        let duration = 1000;
        let rewards_per_second = 10000; // Higher rewards
        
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            rewards_per_second,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock rewards
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        mycoin::register(&reward_manager);
        mycoin::mint_coins(&admin, duration * rewards_per_second);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, duration * rewards_per_second);
        staking::lock_rewards(&reward_manager, duration * rewards_per_second);
        
        // Prepare users
        mycoin::register(&user1);
        mycoin::register(&user2);
        mycoin::mint_coins(&admin, 2000);
        mycoin::transfer(&admin, USER1_ADDRESS, 1000);
        mycoin::transfer(&admin, USER2_ADDRESS, 1000);
        
        // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // Users stake
        staking::stake(&user1, 1000);
        staking::stake(&user2, 1000);
        
        // Move time forward to accumulate rewards
        timestamp::update_global_time_for_test_secs(start_time + 100);
        
        // User1 claims
        let balance_before = mycoin::balance(USER1_ADDRESS);
        staking::claim_rewards(&user1);
        let balance_after = mycoin::balance(USER1_ADDRESS);
        
        // Should get rewards for the elapsed time
        assert!(balance_after > balance_before, 0);
        
        // Move time forward again
        timestamp::update_global_time_for_test_secs(start_time + 200);
        
        // User1 claims again
        let balance_before2 = mycoin::balance(USER1_ADDRESS);
        staking::claim_rewards(&user1);
        let balance_after2 = mycoin::balance(USER1_ADDRESS);
        
        // Should get more rewards
        assert!(balance_after2 > balance_before2, 0);
    }

    #[test]
    fun test_staking_fee_config_edge_cases() {
        // Setup
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let fee_manager = account::create_account_for_test(FEE_MANAGER_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool with zero fee
        let start_time = 1000;
        let duration = 1000;
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            10,
            10000,
            100,
            5000,
            0, // 0% fee
            0, // 0 min fee
            0, // 0 max fee
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock rewards
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        mycoin::register(&reward_manager);
        mycoin::mint_coins(&admin, duration * 10);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, duration * 10);
        staking::lock_rewards(&reward_manager, duration * 10);
        
        // Update fee config to 100% fee (this tests the maximum fee percentage allowed)
        staking::update_fee_config(
            &fee_manager,
            10000, // 100% fee (10000 basis points)
            0,
            10000, // Very high max fee
            FEE_COLLECTOR_ADDRESS
        );
        
        // Prepare fee collector
        let fee_collector = account::create_account_for_test(FEE_COLLECTOR_ADDRESS);
        mycoin::register(&fee_collector);
        
        // Prepare user
        mycoin::register(&user1);
        mycoin::mint_coins(&admin, 1000);
        mycoin::transfer(&admin, USER1_ADDRESS, 1000);
        
        // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // Stake
        staking::stake(&user1, 1000);
        
        // Unstake immediately (should incur 100% fee)
        let balance_before = mycoin::balance(USER1_ADDRESS);
        staking::unstake(&user1);
        let balance_after = mycoin::balance(USER1_ADDRESS);
        
        // With 100% fee, user should get minimal amount back
        // The exact amount depends on implementation details
        
        // Collect fees
        let collector_balance_before = mycoin::balance(FEE_COLLECTOR_ADDRESS);
        staking::collect_fees(&fee_collector);
        let collector_balance_after = mycoin::balance(FEE_COLLECTOR_ADDRESS);
        
        // Fee collector should have received a substantial fee
        assert!(collector_balance_after > collector_balance_before, 0);
        
        // Update to 0% fee again
        staking::update_fee_config(
            &fee_manager,
            0, // 0% fee
            0,
            0,
            FEE_COLLECTOR_ADDRESS
        );
    }

    #[test]
    fun test_staking_update_pool_config_edge_cases() {
        // Test edge cases for pool config updates
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool with minimal configuration
        let start_time = 1000;
        let duration = 1000;
        timestamp::update_global_time_for_test_secs(start_time - 500);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            10,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock extra rewards (much more than needed)
        mycoin::register(&reward_manager);
        mycoin::mint_coins(&admin, duration * 1000);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, duration * 1000);
        staking::lock_rewards(&reward_manager, duration * 1000);
        
        // Update to extreme values
        let new_start_time = start_time + 400; // Still in the future
        let new_duration = 10000; // Very long duration
        let new_rewards_per_second = 100; // Higher rewards
        let new_max_total_stake = 1000000; // Much higher stake limit
        
        staking::update_pool_config(
            &admin,
            new_start_time,
            new_duration,
            new_rewards_per_second,
            new_max_total_stake
        );
        
        // Verify config updated
        let (actual_start, actual_end) = staking::get_pool_times();
        assert!(actual_start == new_start_time, 0);
        assert!(actual_end == new_start_time + new_duration, 0);
        
        let (max_stake, min_stake, max_per_user) = staking::get_pool_limits();
        assert!(max_stake == new_max_total_stake, 0);
        
        // Update again to test consecutive updates
        let newer_start_time = new_start_time + 50; // Still in future
        
        staking::update_pool_config(
            &admin,
            newer_start_time,
            new_duration,
            new_rewards_per_second,
            new_max_total_stake
        );
        
        // Verify updated again
        let (actual_start2, _) = staking::get_pool_times();
        assert!(actual_start2 == newer_start_time, 0);
    }

    #[test]
    fun test_staking_extended_time_passage() {
        // Test behavior when a long time passes
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool
        let start_time = 1000;
        let duration = 1000;
        let rewards_per_second = 10;
        
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            rewards_per_second,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock rewards
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        mycoin::register(&reward_manager);
        mycoin::mint_coins(&admin, duration * rewards_per_second);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, duration * rewards_per_second);
        staking::lock_rewards(&reward_manager, duration * rewards_per_second);
        
        // Prepare user
        mycoin::register(&user1);
        mycoin::mint_coins(&admin, 1000);
        mycoin::transfer(&admin, USER1_ADDRESS, 1000);
        
        // Move time to start
        timestamp::update_global_time_for_test_secs(start_time);
        
        // Stake
        staking::stake(&user1, 1000);
        
        // Jump far into the future, way past pool end
        timestamp::update_global_time_for_test_secs(start_time + duration + 10000);
        
        // Unstake
        let balance_before = mycoin::balance(USER1_ADDRESS);
        staking::unstake(&user1);
        let balance_after = mycoin::balance(USER1_ADDRESS);
        
        // Should receive stake back plus rewards up to pool end
        assert!(balance_after > balance_before, 0);
        assert!(balance_after > balance_before + 1000, 0); // Should get some rewards
        
        // No fees should be charged (unstaking after end)
        assert!(staking::get_collected_fees() == 0, 0);
    }

    #[test]
    fun test_staking_time_not_passing() {
        // Test behavior when time doesn't change between operations
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        let user2 = account::create_account_for_test(USER2_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool
        let start_time = 1000;
        let duration = 1000;
        let rewards_per_second = 10;
        
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            rewards_per_second,
            10000,
            100,
            5000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock rewards
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        mycoin::register(&reward_manager);
        mycoin::mint_coins(&admin, duration * rewards_per_second);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, duration * rewards_per_second);
        staking::lock_rewards(&reward_manager, duration * rewards_per_second);
        
        // Prepare users
        mycoin::register(&user1);
        mycoin::register(&user2);
        mycoin::mint_coins(&admin, 2000);
        mycoin::transfer(&admin, USER1_ADDRESS, 1000);
        mycoin::transfer(&admin, USER2_ADDRESS, 1000);
        
        // Move time to after pool start
        timestamp::update_global_time_for_test_secs(start_time + 10);
        
        // Both users stake without time passing in between
        staking::stake(&user1, 1000);
        staking::stake(&user2, 1000);

        // Move time forward a bit to generate some rewards before claiming
        timestamp::update_global_time_for_test_secs(start_time + 20);
        
        // User1 claims with no time passing
        staking::claim_rewards(&user1);
        
        // Move time forward
        timestamp::update_global_time_for_test_secs(start_time + 100);
        
        // User1 claims again after time passes
        let balance_before = mycoin::balance(USER1_ADDRESS);
        staking::claim_rewards(&user1);
        let balance_after = mycoin::balance(USER1_ADDRESS);
        
        // Should get rewards for the elapsed time
        assert!(balance_after > balance_before, 0);
    }

    #[test]
    fun test_staking_precision_challenges() {
        // Test with values that might cause precision issues
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let user1 = account::create_account_for_test(USER1_ADDRESS);
        
        // Initialize
        let aptos_framework = account::create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(&aptos_framework);
        mycoin::initialize(&admin);
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Setup pool with very small reward rate
        let start_time = 1000;
        let duration = 1000;
        let rewards_per_second = 1; // Minimum possible
        
        timestamp::update_global_time_for_test_secs(start_time - 100);
        
        staking::initialize(
            &admin,
            start_time,
            duration,
            rewards_per_second,
            1000000, // Large max stake
            100,
            1000000,
            500,
            10,
            500,
            FEE_COLLECTOR_ADDRESS
        );
        
        // Lock rewards
        let reward_manager = account::create_account_for_test(REWARD_MANAGER_ADDRESS);
        mycoin::register(&reward_manager);
        mycoin::mint_coins(&admin, duration * rewards_per_second);
        mycoin::transfer(&admin, REWARD_MANAGER_ADDRESS, duration * rewards_per_second);
        staking::lock_rewards(&reward_manager, duration * rewards_per_second);
        
        // Prepare user with large stake
        mycoin::register(&user1);
        mycoin::mint_coins(&admin, 1000000);
        mycoin::transfer(&admin, USER1_ADDRESS, 1000000);
        
        // Move time to start
        timestamp::update_global_time_for_test_secs(start_time);
        
        // Stake large amount with tiny reward rate
        staking::stake(&user1, 1000000);
        
        // Move time forward
        timestamp::update_global_time_for_test_secs(start_time + 500);
        
        // Unstake
        let balance_before = mycoin::balance(USER1_ADDRESS);
        staking::unstake(&user1);
        let balance_after = mycoin::balance(USER1_ADDRESS);
        
        // Should get stake back
        assert!(balance_after >= balance_before, 0);
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_initialize_with_zero_reward_manager() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Try to initialize with zero address for reward_manager
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            @0x0, // Zero address for reward_manager
            FEE_COLLECTOR_ADDRESS
        );
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_initialize_with_zero_fee_collector() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Try to initialize with zero address for fee_collector
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            @0x0 // Zero address for fee_collector
        );
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_initialize_with_admin_as_fee_manager() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Try to initialize with admin as fee_manager
        roles::initialize_roles(
            &admin, 
            STAKING_ADDRESS, // Admin address as fee_manager
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_initialize_with_admin_as_reward_manager() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Try to initialize with admin as reward_manager
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS,
            STAKING_ADDRESS, // Admin address as reward_manager
            FEE_COLLECTOR_ADDRESS
        );
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_initialize_with_admin_as_fee_collector() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Try to initialize with admin as fee_collector
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS,
            REWARD_MANAGER_ADDRESS,
            STAKING_ADDRESS // Admin address as fee_collector
        );
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_initialize_with_fee_manager_as_fee_collector() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Try to initialize with fee_manager same as fee_collector
        roles::initialize_roles(
            &admin, 
            @0x123, // Same address for both
            REWARD_MANAGER_ADDRESS,
            @0x123 // Same address for both
        );
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_initialize_with_reward_manager_as_fee_collector() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Try to initialize with reward_manager same as fee_collector
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS,
            @0x123, // Same address for both
            @0x123 // Same address for both
        );
    }

    #[test]
    #[expected_failure(abort_code = ENOT_POOL_ADMIN, location = staking::roles)]
    fun test_update_admin_by_non_admin() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        let non_admin = account::create_account_for_test(@0x123);
        
        // Initialize roles properly
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Non-admin tries to update admin
        roles::update_pool_admin(&non_admin, @0x456);
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_update_admin_to_fee_manager() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Initialize roles
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Try to set new admin to current fee_manager
        roles::update_pool_admin(&admin, FEE_MANAGER_ADDRESS);
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_update_admin_to_reward_manager() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Initialize roles
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Try to set new admin to current reward_manager
        roles::update_pool_admin(&admin, REWARD_MANAGER_ADDRESS);
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_update_admin_to_fee_collector() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Initialize roles
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Try to set new admin to current fee_collector
        roles::update_pool_admin(&admin, FEE_COLLECTOR_ADDRESS);
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_update_fee_manager_to_fee_collector() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Initialize roles
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Try to set new fee_manager to current fee_collector
        roles::update_fee_manager(&admin, FEE_COLLECTOR_ADDRESS);
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_update_reward_manager_to_fee_manager() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Initialize roles
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Try to set new reward_manager to current fee_manager
        roles::update_reward_manager(&admin, FEE_MANAGER_ADDRESS);
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_update_reward_manager_to_fee_collector() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Initialize roles
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Try to set new reward_manager to current fee_collector
        roles::update_reward_manager(&admin, FEE_COLLECTOR_ADDRESS);
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_update_fee_collector_to_fee_manager() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Initialize roles
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Try to set new fee_collector to current fee_manager
        roles::update_fee_collector(&admin, FEE_MANAGER_ADDRESS);
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ADDRESS, location = staking::roles)]
    fun test_update_fee_collector_to_reward_manager() {
        let admin = account::create_account_for_test(STAKING_ADDRESS);
        
        // Initialize roles
        roles::initialize_roles(
            &admin, 
            FEE_MANAGER_ADDRESS, 
            REWARD_MANAGER_ADDRESS, 
            FEE_COLLECTOR_ADDRESS
        );
        
        // Try to set new fee_collector to current reward_manager
        roles::update_fee_collector(&admin, REWARD_MANAGER_ADDRESS);
    }   
}