module staking::staking {
    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::event;
    use aptos_framework::simple_map::{Self, SimpleMap};
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use staking::mycoin::MyCoin;

    struct StakingInfo has key {
        total_staked: u64,
        rewards_per_second: u64,
        end_time: u64,
        early_unstake_fee: u64,
        stakes: SimpleMap<address, u64>,
        signer_cap: account::SignerCapability,
        admin: address,
        fee_collector: address,
        collected_fees: u64,
        stake_events: event::EventHandle<StakedEvent>,
        unstake_events: event::EventHandle<UnstakedEvent>,
        fee_withdrawn_events: event::EventHandle<FeeWithdrawnEvent>
    }

    struct StakedEvent has drop, store {
        user: address,
        amount: u64,
    }

    struct UnstakedEvent has drop, store {
        user: address,
        amount: u64,
        fee_charged: u64,
    }

    struct FeeWithdrawnEvent has drop, store {
        collector: address,
        amount: u64,
    }

    const INVALID_ADMIN: u64 = 1;
    const INVALID_FEE_COLLECTOR: u64 = 100;

    public entry fun initialize(admin: &signer, rewards_per_second: u64, duration: u64, early_unstake_fee: u64, fee_collector: address) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @staking, INVALID_ADMIN);

        let (resource_account, signer_cap) = account::create_resource_account(admin, b"staking");
        coin::register<MyCoin>(&resource_account);

        move_to(admin, StakingInfo {
            total_staked: 0,
            rewards_per_second,
            end_time: timestamp::now_seconds() + duration,
            early_unstake_fee,
            stakes: simple_map::create(),
            signer_cap,
            admin: admin_addr,
            fee_collector,
            collected_fees: 0,
            stake_events: account::new_event_handle<StakedEvent>(admin),
            unstake_events: account::new_event_handle<UnstakedEvent>(admin),
            fee_withdrawn_events: account::new_event_handle<FeeWithdrawnEvent>(admin)
        });
    }

    public entry fun stake(user: &signer, amount: u64) acquires StakingInfo {
        let user_addr = signer::address_of(user);
        let staking_info = borrow_global_mut<StakingInfo>(@staking);
        let resource_signer = account::create_signer_with_capability(&staking_info.signer_cap);
        
        coin::transfer<MyCoin>(user, signer::address_of(&resource_signer), amount);
        
        if (!simple_map::contains_key(&staking_info.stakes, &user_addr)) {
            simple_map::add(&mut staking_info.stakes, user_addr, amount);
        } else {
            let current_stake = simple_map::borrow_mut(&mut staking_info.stakes, &user_addr);
            *current_stake = *current_stake + amount;
        };
        
        staking_info.total_staked = staking_info.total_staked + amount;
        
        event::emit_event(&mut staking_info.stake_events, StakedEvent { 
            user: user_addr, 
            amount 
        });
    }

    public entry fun unstake(user: &signer) acquires StakingInfo {
        let user_addr = signer::address_of(user);
        let staking_info = borrow_global_mut<StakingInfo>(@staking);
        let now = timestamp::now_seconds();
        
        assert!(simple_map::contains_key(&staking_info.stakes, &user_addr), 2);
        let stake_amount = *simple_map::borrow(&staking_info.stakes, &user_addr);
        simple_map::remove(&mut staking_info.stakes, &user_addr);
        
        let resource_signer = account::create_signer_with_capability(&staking_info.signer_cap);
        let mut_fee = 0u64;

        if (now < staking_info.end_time) {
            mut_fee = (stake_amount * staking_info.early_unstake_fee) / 100;
            staking_info.collected_fees = staking_info.collected_fees + mut_fee;
        };

        let reward = if (staking_info.total_staked > 0) {
            (stake_amount * staking_info.rewards_per_second * (now - timestamp::now_seconds())) / staking_info.total_staked
        } else {
            0
        };
        
        let withdraw_amount = stake_amount - mut_fee + reward;
        staking_info.total_staked = staking_info.total_staked - stake_amount;
        
        coin::transfer<MyCoin>(&resource_signer, user_addr, withdraw_amount);
        
        event::emit_event(&mut staking_info.unstake_events, UnstakedEvent { 
            user: user_addr, 
            amount: withdraw_amount, 
            fee_charged: mut_fee 
        });
    }

    public entry fun withdraw_fees(collector: &signer) acquires StakingInfo {
        let collector_addr = signer::address_of(collector);
        let staking_info = borrow_global_mut<StakingInfo>(@staking);
        assert!(collector_addr == staking_info.fee_collector, INVALID_FEE_COLLECTOR);
        
        let amount = staking_info.collected_fees;
        staking_info.collected_fees = 0;
        let resource_signer = account::create_signer_with_capability(&staking_info.signer_cap);
        
        coin::transfer<MyCoin>(&resource_signer, collector_addr, amount);
        event::emit_event(&mut staking_info.fee_withdrawn_events, FeeWithdrawnEvent { 
            collector: collector_addr, 
            amount 
        });
    }
}