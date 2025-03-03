module staking::staking {
    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::account;
    use aptos_framework::simple_map::{Self, SimpleMap};
    use aptos_framework::timestamp;
    use staking::mycoin::MyCoin;
    use staking::roles;
    use std::option::{Self, Option};

    struct FeeConfig has store, copy, drop {
        early_unstake_fee_percentage: u64,
        minimum_fee: u64,
        maximum_fee: u64,
        fee_collection_address: address
    }

    struct PoolConfig has store, copy, drop {
        start_time: u64,
        end_time: u64,
        rewards_per_second: u64,
        max_total_stake: u64,
        min_stake_amount: u64,
        max_stake_per_user: u64,
        fee_config: FeeConfig
    }

    struct UserInfo has store, copy, drop {
        staked_amount: u64,
        reward_debt: u64,
        last_update_time: u64,
        lock_end_time: Option<u64>
    }

    struct StakingInfo has key {
        pool_config: PoolConfig,
        total_staked: u64,
        accumulated_rewards_per_stake: u64,
        locked_rewards: u64,
        last_update_time: u64,
        stakes: SimpleMap<address, UserInfo>,
        signer_cap: account::SignerCapability,
        collected_fees: u64,
        stake_events: event::EventHandle<StakedEvent>,
        unstake_events: event::EventHandle<UnstakedEvent>,
        reward_claim_events: event::EventHandle<RewardClaimEvent>,
        fee_events: event::EventHandle<FeeEvent>,
        pool_update_events: event::EventHandle<PoolUpdateEvent>
    }

    struct StakedEvent has store, drop {
        user: address,
        amount: u64,
        timestamp: u64
    }

    struct UnstakedEvent has store, drop {
        user: address,
        amount: u64,
        fee_charged: u64,
        rewards_claimed: u64,
        timestamp: u64
    }

    struct RewardClaimEvent has store, drop {
        user: address,
        amount: u64,
        timestamp: u64
    }

    struct FeeEvent has store, drop {
        collector: address,
        amount: u64,
        fee_percentage: Option<u64>,        // 10000BP = 100%
        minimum_fee: Option<u64>,
        maximum_fee: Option<u64>,
        timestamp: u64    
    }

    struct PoolUpdateEvent has store, drop {
        start_time: u64,
        end_time: u64,
        rewards_per_second: u64,
        max_total_stake: u64,
        timestamp: u64
    }

    const PRECISION_FACTOR: u64 = 1000000;

    const INVALID_ADMIN: u64 = 1;
    const NO_STAKE_FOUND: u64 = 2;
    const POOL_NOT_STARTED: u64 = 3;
    const POOL_ENDED: u64 = 4;
    const STAKE_TOO_LOW: u64 = 5;
    const POOL_ALREADY_STARTED: u64 = 6;
    const STAKE_TOO_HIGH: u64 = 7;
    const POOL_FULL: u64 = 8;
    const STILL_LOCKED: u64 = 9;
    const INVALID_FEE_PERCENTAGE: u64 = 10;
    const INVALID_FEE_LIMITS: u64 = 11;
    const NOT_FEE_COLLECTOR: u64 = 12;
    const NO_FEES_TO_COLLECT: u64 = 13;
    const NO_REWARDS_TO_CLAIM: u64 = 14;
    const NOT_ENOUGH_REWARDS_LOCKED: u64 = 15;

    public entry fun initialize(
        admin: &signer,
        start_time: u64,
        duration: u64,
        rewards_per_second: u64,
        max_total_stake: u64,
        min_stake_amount: u64,
        max_stake_per_user: u64,
        fee_percentage: u64,                // 10000 BP = 100%
        min_fee: u64,
        max_fee: u64,
        fee_collector: address
    ) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @staking, INVALID_ADMIN);

        let seed = x"f6d7179133829893b3623e8d48783875a4792afb9bbc973874d983cf94ad8da5";
        let (resource_account, signer_cap) = account::create_resource_account(admin, seed);
        coin::register<MyCoin>(&resource_account);

        let current_time = timestamp::now_seconds();

        move_to(admin, StakingInfo {
            pool_config: PoolConfig {
                start_time,
                end_time: start_time + duration,
                rewards_per_second,
                max_total_stake,
                min_stake_amount,
                max_stake_per_user,
                fee_config: FeeConfig {
                    early_unstake_fee_percentage: fee_percentage,
                    minimum_fee: min_fee,
                    maximum_fee: max_fee,
                    fee_collection_address: fee_collector
                }
            },
            total_staked: 0,
            accumulated_rewards_per_stake: 0,
            locked_rewards: 0,
            last_update_time: current_time,
            stakes: simple_map::new(),
            signer_cap,
            collected_fees: 0,
            stake_events: account::new_event_handle<StakedEvent>(admin),
            unstake_events: account::new_event_handle<UnstakedEvent>(admin),
            reward_claim_events: account::new_event_handle<RewardClaimEvent>(admin),
            fee_events: account::new_event_handle<FeeEvent>(admin),
            pool_update_events: account::new_event_handle<PoolUpdateEvent>(admin)
        });
    }

    public entry fun stake(user: &signer, amount: u64) acquires StakingInfo {
        let user_addr = signer::address_of(user);
        let staking_info = borrow_global_mut<StakingInfo>(@staking);
        let current_time = timestamp::now_seconds();

        assert!(current_time >= staking_info.pool_config.start_time, POOL_NOT_STARTED);
        assert!(current_time < staking_info.pool_config.end_time, POOL_ENDED);
        assert!(amount >= staking_info.pool_config.min_stake_amount, STAKE_TOO_LOW);

        update_pool_rewards(staking_info);

        let resource_signer = account::create_signer_with_capability(&staking_info.signer_cap);
        coin::transfer<MyCoin>(user, signer::address_of(&resource_signer), amount);

        if (!simple_map::contains_key(&staking_info.stakes, &user_addr)) {
            assert!(amount <= staking_info.pool_config.max_stake_per_user, STAKE_TOO_HIGH);

            simple_map::add(&mut staking_info.stakes, user_addr, UserInfo {
                staked_amount: amount,
                reward_debt: (amount * staking_info.accumulated_rewards_per_stake) / PRECISION_FACTOR,
                last_update_time: current_time,
                lock_end_time: option::none()
            });
        } else {
            // Get current user info
            let user_info = *simple_map::borrow(&staking_info.stakes, &user_addr);
            
            // Calculate pending rewards with the current state before updating
            let pending_reward = calculate_pending_rewards(staking_info, user_info);
            
            // Update staking amount
            let new_stake = user_info.staked_amount + amount;
            assert!(new_stake <= staking_info.pool_config.max_stake_per_user, STAKE_TOO_HIGH);
            
            // Calculate new reward debt
            let new_reward_debt = ((new_stake * staking_info.accumulated_rewards_per_stake) / PRECISION_FACTOR) - pending_reward;
            
            // Update the user info in the map
            let updated_user_info = UserInfo {
                staked_amount: new_stake,
                reward_debt: new_reward_debt,
                last_update_time: current_time,
                lock_end_time: user_info.lock_end_time
            };
            *simple_map::borrow_mut(&mut staking_info.stakes, &user_addr) = updated_user_info;
        };

        let new_total = staking_info.total_staked + amount;
        assert!(new_total <= staking_info.pool_config.max_total_stake, POOL_FULL);
        staking_info.total_staked = new_total;

        event::emit_event(&mut staking_info.stake_events, StakedEvent {
            user: user_addr,
            amount,
            timestamp: current_time
        });
    }

    public entry fun unstake(user: &signer) acquires StakingInfo {
        let user_addr = signer::address_of(user);
        let staking_info = borrow_global_mut<StakingInfo>(@staking);
        let current_time = timestamp::now_seconds();

        assert!(simple_map::contains_key(&staking_info.stakes, &user_addr), NO_STAKE_FOUND);
        
        // Create a copy of user info
        let user_info = *simple_map::borrow(&staking_info.stakes, &user_addr);

        if (option::is_some(&user_info.lock_end_time)) {
            assert!(current_time >= *option::borrow(&user_info.lock_end_time), STILL_LOCKED);
        };

        update_pool_rewards(staking_info);
        
        // Calculate pending rewards and fee
        let pending_reward = calculate_pending_rewards(staking_info, user_info);
        let fee = calculate_unstake_fee(staking_info, user_info.staked_amount, current_time);
        
        // Update staking info
        staking_info.collected_fees = staking_info.collected_fees + fee;
        staking_info.total_staked = staking_info.total_staked - user_info.staked_amount;
        
        let withdraw_amount = user_info.staked_amount + pending_reward - fee;

        // Remove the user from the stakes map
        simple_map::remove(&mut staking_info.stakes, &user_addr);

        let resource_signer = account::create_signer_with_capability(&staking_info.signer_cap);
        coin::transfer<MyCoin>(&resource_signer, user_addr, withdraw_amount);

        event::emit_event(&mut staking_info.unstake_events, UnstakedEvent {
            user: user_addr,
            amount: withdraw_amount,
            fee_charged: fee,
            rewards_claimed: pending_reward,
            timestamp: current_time
        });
    }

    public entry fun claim_rewards(user: &signer) acquires StakingInfo {
        let user_addr = signer::address_of(user);
        let staking_info = borrow_global_mut<StakingInfo>(@staking);
        let current_time = timestamp::now_seconds();

        assert!(simple_map::contains_key(&staking_info.stakes, &user_addr), NO_STAKE_FOUND);

        update_pool_rewards(staking_info);

        // Get a copy of the user info first
        let user_info = *simple_map::borrow(&staking_info.stakes, &user_addr);
        let pending_rewards = calculate_pending_rewards(staking_info, user_info);
        assert!(pending_rewards > 0, NO_REWARDS_TO_CLAIM);

        // Update the reward debt in the map
        let updated_user_info = UserInfo {
            staked_amount: user_info.staked_amount,
            reward_debt: (user_info.staked_amount * staking_info.accumulated_rewards_per_stake) / PRECISION_FACTOR,
            last_update_time: current_time,
            lock_end_time: user_info.lock_end_time
        };
        *simple_map::borrow_mut(&mut staking_info.stakes, &user_addr) = updated_user_info;

        // Transfer rewards
        let resource_signer = account::create_signer_with_capability(&staking_info.signer_cap);
        coin::transfer<MyCoin>(&resource_signer, user_addr, pending_rewards);

        event::emit_event(&mut staking_info.reward_claim_events, RewardClaimEvent {
            user: user_addr,
            amount: pending_rewards,
            timestamp: current_time
        });
    }

    public entry fun update_pool_config(
        admin: &signer,
        new_start_time: u64,
        new_duration: u64,
        new_rewards_per_second: u64,
        new_max_total_stake: u64
    ) acquires StakingInfo {
        roles::verify_pool_admin(admin);

        let staking_info = borrow_global_mut<StakingInfo>(@staking);
        let current_time = timestamp::now_seconds();

        assert!(current_time < staking_info.pool_config.start_time, POOL_ALREADY_STARTED);

        let new_end_time = new_start_time + new_duration;
        
        // Check that enough rewards are locked
        let required_rewards = new_rewards_per_second * new_duration;
        assert!(staking_info.locked_rewards >= required_rewards, NOT_ENOUGH_REWARDS_LOCKED);

        staking_info.pool_config.start_time = new_start_time;
        staking_info.pool_config.end_time = new_end_time;
        staking_info.pool_config.rewards_per_second = new_rewards_per_second;
        staking_info.pool_config.max_total_stake = new_max_total_stake;

        event::emit_event(&mut staking_info.pool_update_events, PoolUpdateEvent {
            start_time: new_start_time,
            end_time: new_end_time,
            rewards_per_second: new_rewards_per_second,
            max_total_stake: new_max_total_stake,
            timestamp: current_time
        });
    }

    public entry fun update_fee_config(
        fee_manager: &signer,
        new_fee_percentage: u64,
        new_minimum_fee: u64,
        new_maximum_fee: u64,
        new_fee_collector: address
    ) acquires StakingInfo {
        roles::verify_fee_manager(fee_manager);

        assert!(new_fee_percentage <= 10000, INVALID_FEE_PERCENTAGE); // 10000 Basis Points = 100%
        assert!(new_minimum_fee <= new_maximum_fee, INVALID_FEE_LIMITS);

        let staking_info = borrow_global_mut<StakingInfo>(@staking);
        let current_time = timestamp::now_seconds();

        staking_info.pool_config.fee_config = FeeConfig {
            early_unstake_fee_percentage: new_fee_percentage,
            minimum_fee: new_minimum_fee,
            maximum_fee: new_maximum_fee,
            fee_collection_address: new_fee_collector
        };

        event::emit_event(&mut staking_info.fee_events, FeeEvent {
            collector: new_fee_collector,
            amount: 0,
            fee_percentage: option::some(new_fee_percentage),
            minimum_fee: option::some(new_minimum_fee),
            maximum_fee: option::some(new_maximum_fee),
            timestamp: current_time
        });
    }

    public entry fun collect_fees(collector: &signer) acquires StakingInfo {
        let collector_addr = signer::address_of(collector);
        let staking_info = borrow_global_mut<StakingInfo>(@staking);
        let current_time = timestamp::now_seconds();

        assert!(collector_addr == staking_info.pool_config.fee_config.fee_collection_address,
            NOT_FEE_COLLECTOR);

        let fee_amount = staking_info.collected_fees;
        assert!(fee_amount > 0, NO_FEES_TO_COLLECT);

        staking_info.collected_fees = 0;

        let resource_signer = account::create_signer_with_capability(&staking_info.signer_cap);
        coin::transfer<MyCoin>(&resource_signer, collector_addr, fee_amount);

        event::emit_event(&mut staking_info.fee_events, FeeEvent {
            collector: collector_addr,
            amount: fee_amount,
            fee_percentage: option::none(),
            minimum_fee: option::none(),
            maximum_fee: option::none(),
            timestamp: current_time
        });
    }

    public entry fun lock_rewards(reward_manager: &signer, amount: u64) acquires StakingInfo {
        roles::verify_reward_manager(reward_manager);
        let pool = borrow_global_mut<StakingInfo>(@staking);
        let current_time = timestamp::now_seconds();

        assert!(current_time < pool.pool_config.start_time, POOL_ALREADY_STARTED);

        let resource_signer = account::create_signer_with_capability(&pool.signer_cap);
        coin::transfer<MyCoin>(reward_manager, signer::address_of(&resource_signer), amount);

        pool.locked_rewards = pool.locked_rewards + amount;
    }

    public entry fun unlock_rewards(reward_manager: &signer, amount: u64) acquires StakingInfo {
        roles::verify_reward_manager(reward_manager);
        let pool = borrow_global_mut<StakingInfo>(@staking);
        let current_time = timestamp::now_seconds();

        assert!(current_time < pool.pool_config.start_time, POOL_ALREADY_STARTED);
        assert!(amount <= pool.locked_rewards, NO_REWARDS_TO_CLAIM);

        let resource_signer = account::create_signer_with_capability(&pool.signer_cap);
        coin::transfer<MyCoin>(&resource_signer, signer::address_of(reward_manager), amount);

        pool.locked_rewards = pool.locked_rewards - amount;
    }

    fun calculate_pending_rewards(
    pool: &StakingInfo,
    user_info: UserInfo
): u64 {
    if (user_info.staked_amount == 0) {
        return 0
    };

    // Update pool rewards first to ensure accumulated_rewards_per_stake is up to date
    let current_accumulated = pool.accumulated_rewards_per_stake;
    
    // Calculate rewards based on accumulated reward per stake
    let reward = (user_info.staked_amount * current_accumulated) / PRECISION_FACTOR;
    
    // Subtract the reward debt to get pending rewards
    if (reward > user_info.reward_debt) {
        reward - user_info.reward_debt
    } else {
        0
    }
}

   fun update_pool_rewards(pool: &mut StakingInfo) {
    let current_time = timestamp::now_seconds();
    
    // If no stakes, just update the timestamp and return
    if (pool.total_staked == 0) {
        pool.last_update_time = current_time;
        return
    };
    
    // Calculate effective time bounds
    let pool_start = pool.pool_config.start_time;
    let pool_end = pool.pool_config.end_time;
    
    // No rewards before pool starts
    if (current_time < pool_start) {
        pool.last_update_time = current_time;
        return
    };
    
    // Get effective last update time (max of last_update_time and pool_start)
    let effective_last_update = if (pool.last_update_time < pool_start) {
        pool_start
    } else {
        pool.last_update_time
    };
    
    // Get effective current time (min of current_time and pool_end)
    let effective_current_time = if (current_time > pool_end) {
        pool_end
    } else {
        current_time
    };
    
    // Calculate rewards if time has passed within the active period
    if (effective_current_time > effective_last_update) {
        let time_passed = effective_current_time - effective_last_update;
        
        // Calculate total rewards for this period
        let total_rewards = pool.pool_config.rewards_per_second * time_passed;
        
        // Calculate reward per staked token with precision scaling
        let reward_per_stake = (total_rewards * PRECISION_FACTOR) / pool.total_staked;
        
        pool.accumulated_rewards_per_stake = pool.accumulated_rewards_per_stake + reward_per_stake;
    };
    
    // Always update the last update time
    pool.last_update_time = current_time;
}

    fun calculate_unstake_fee(
        pool: &StakingInfo,
        stake_amount: u64,
        unstake_time: u64
    ): u64 {
        let fee_config = &pool.pool_config.fee_config;

        // Only charge fee if unstaking before pool end time
        if (unstake_time >= pool.pool_config.end_time) {
            return 0
        };

        let base_fee = (stake_amount * fee_config.early_unstake_fee_percentage) / 10000;

        if (base_fee < fee_config.minimum_fee) {
            fee_config.minimum_fee
        } else if (base_fee > fee_config.maximum_fee) {
            fee_config.maximum_fee
        } else {
            base_fee
        }
    }

    fun min(a: u64, b: u64): u64 {
        if (a < b) { a } else { b }
    }

    #[view]
    public fun get_pool_config(): PoolConfig acquires StakingInfo {
        borrow_global<StakingInfo>(@staking).pool_config
    }

    #[view]
    public fun get_user_info(user: address): Option<UserInfo> acquires StakingInfo {
        let staking_info = borrow_global<StakingInfo>(@staking);
        if (simple_map::contains_key(&staking_info.stakes, &user)) {
            option::some(*simple_map::borrow(&staking_info.stakes, &user))
        } else {
            option::none()
        }
    }

    #[view]
    public fun get_pending_rewards(user: address): u64 acquires StakingInfo {
        let staking_info = borrow_global<StakingInfo>(@staking);
        if (!simple_map::contains_key(&staking_info.stakes, &user)) {
            return 0
        };
        calculate_pending_rewards(staking_info, *simple_map::borrow(&staking_info.stakes, &user))
    }

    #[view]
    public fun get_fee_config(): FeeConfig acquires StakingInfo {
        borrow_global<StakingInfo>(@staking).pool_config.fee_config
    }

    #[view]
    public fun get_collected_fees(): u64 acquires StakingInfo {
        borrow_global<StakingInfo>(@staking).collected_fees
    }

    #[view]
    public fun get_pool_stats(): (u64, u64, u64, u64) acquires StakingInfo {
        let pool = borrow_global<StakingInfo>(@staking);
        (
            pool.total_staked,
            pool.locked_rewards,
            pool.accumulated_rewards_per_stake,
            pool.last_update_time
        )
    }

    #[view]
    public fun get_pool_times(): (u64, u64) acquires StakingInfo {
        let pool = borrow_global<StakingInfo>(@staking);
        (
            pool.pool_config.start_time,
            pool.pool_config.end_time
        )
    }

    #[view]
    public fun get_pool_limits(): (u64, u64, u64) acquires StakingInfo {
        let pool = borrow_global<StakingInfo>(@staking);
        (
            pool.pool_config.max_total_stake,
            pool.pool_config.min_stake_amount,
            pool.pool_config.max_stake_per_user
        )
    }

    #[view]
    public fun is_pool_active(): bool acquires StakingInfo {
        let pool = borrow_global<StakingInfo>(@staking);
        let current_time = timestamp::now_seconds();
        current_time >= pool.pool_config.start_time && current_time < pool.pool_config.end_time
    }
}