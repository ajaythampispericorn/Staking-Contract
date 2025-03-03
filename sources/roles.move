module staking::roles {
    use std::signer;

    struct Roles has key {
        pool_admin: address,
        fee_manager: address,
        reward_manager: address,
        fee_collector: address
    }

    //Error Codes
    const ENOT_POOL_ADMIN: u64 = 1;
    const ENOT_FEE_MANAGER: u64 = 2;
    const ENOT_REWARD_MANAGER: u64 = 3;
    const EINVALID_ADDRESS: u64 = 4;
    const EROLES_ALREADY_INITIALIZED: u64 = 5;
    const ENOT_AUTHORIZED: u64 = 6;

    public fun initialize_roles(
    admin: &signer,
    fee_manager: address,
    reward_manager: address,
    fee_collector: address
) {
    let admin_addr = signer::address_of(admin);
    assert!(admin_addr == @staking, ENOT_POOL_ADMIN);
    assert!(!exists<Roles>(@staking), EROLES_ALREADY_INITIALIZED);

    // Add validation for zero addresses
    assert!(fee_manager != @0x0, EINVALID_ADDRESS);
    assert!(reward_manager != @0x0, EINVALID_ADDRESS);
    assert!(fee_collector != @0x0, EINVALID_ADDRESS);

    // Ensure all roles are different addresses
    assert!(admin_addr != fee_manager, EINVALID_ADDRESS);
    assert!(admin_addr != reward_manager, EINVALID_ADDRESS);
    assert!(admin_addr != fee_collector, EINVALID_ADDRESS);
    assert!(fee_manager != reward_manager, EINVALID_ADDRESS);
    assert!(fee_manager != fee_collector, EINVALID_ADDRESS);
    assert!(reward_manager != fee_collector, EINVALID_ADDRESS);

    move_to(admin, Roles {
        pool_admin: admin_addr,
        fee_manager,
        reward_manager,
        fee_collector
    });
}

    public fun update_pool_admin(admin: &signer, new_admin: address) acquires Roles {
        let admin_addr = signer::address_of(admin);
        assert!(is_pool_admin(admin_addr), ENOT_POOL_ADMIN);
        
        let roles = borrow_global_mut<Roles>(@staking);
        
        // Ensure new admin is not already holding another role
        assert!(new_admin != roles.fee_manager, EINVALID_ADDRESS);
        assert!(new_admin != roles.reward_manager, EINVALID_ADDRESS);
        assert!(new_admin != roles.fee_collector, EINVALID_ADDRESS);
        
        roles.pool_admin = new_admin;
    }

    public fun update_fee_manager(admin: &signer, new_fee_manager: address) acquires Roles {
        let admin_addr = signer::address_of(admin);
        assert!(is_pool_admin(admin_addr), ENOT_AUTHORIZED);
        
        let roles = borrow_global_mut<Roles>(@staking);
        
        // Ensure new fee manager is not already holding another role
        assert!(new_fee_manager != roles.pool_admin, EINVALID_ADDRESS);
        assert!(new_fee_manager != roles.reward_manager, EINVALID_ADDRESS);
        assert!(new_fee_manager != roles.fee_collector, EINVALID_ADDRESS);
        
        roles.fee_manager = new_fee_manager;
    }

    public fun update_reward_manager(admin: &signer, new_reward_manager: address) acquires Roles {
        let admin_addr = signer::address_of(admin);
        assert!(is_pool_admin(admin_addr), ENOT_AUTHORIZED);
        
        let roles = borrow_global_mut<Roles>(@staking);
        
        // Ensure new reward manager is not already holding another role
        assert!(new_reward_manager != roles.pool_admin, EINVALID_ADDRESS);
        assert!(new_reward_manager != roles.fee_manager, EINVALID_ADDRESS);
        assert!(new_reward_manager != roles.fee_collector, EINVALID_ADDRESS);
        
        roles.reward_manager = new_reward_manager;
    }

    public fun update_fee_collector(admin: &signer, new_fee_collector: address) acquires Roles {
        let admin_addr = signer::address_of(admin);
        assert!(is_pool_admin(admin_addr), ENOT_AUTHORIZED);
        
        let roles = borrow_global_mut<Roles>(@staking);
        
        // Ensure new fee collector is not already holding another role
        assert!(new_fee_collector != roles.pool_admin, EINVALID_ADDRESS);
        assert!(new_fee_collector != roles.fee_manager, EINVALID_ADDRESS);
        assert!(new_fee_collector != roles.reward_manager, EINVALID_ADDRESS);
        
        roles.fee_collector = new_fee_collector;
    }

    public fun verify_pool_admin(account: &signer) acquires Roles {
        assert!(is_pool_admin(signer::address_of(account)), ENOT_POOL_ADMIN);
    }

    public fun verify_fee_manager(account: &signer) acquires Roles {
        assert!(is_fee_manager(signer::address_of(account)), ENOT_FEE_MANAGER);
    }

    public fun verify_reward_manager(account: &signer) acquires Roles {
        assert!(is_reward_manager(signer::address_of(account)), ENOT_REWARD_MANAGER);
    }

    public fun verify_fee_collector(account: &signer) acquires Roles {
        assert!(is_fee_collector(signer::address_of(account)), ENOT_FEE_MANAGER);
    }

    public fun is_pool_admin(addr: address): bool acquires Roles {
        let roles = borrow_global<Roles>(@staking);
        roles.pool_admin == addr
    }

    public fun is_fee_manager(addr: address): bool acquires Roles {
        let roles = borrow_global<Roles>(@staking);
        roles.fee_manager == addr
    }

    public fun is_reward_manager(addr: address): bool acquires Roles {
        let roles = borrow_global<Roles>(@staking);
        roles.reward_manager == addr
    }

    public fun is_fee_collector(addr: address): bool acquires Roles {
        let roles = borrow_global<Roles>(@staking);
        roles.fee_collector == addr
    }

    #[view]
    public fun get_pool_admin(): address acquires Roles {
        borrow_global<Roles>(@staking).pool_admin
    }

    #[view]
    public fun get_fee_manager(): address acquires Roles {
        borrow_global<Roles>(@staking).fee_manager
    }

    #[view]
    public fun get_reward_manager(): address acquires Roles {
        borrow_global<Roles>(@staking).reward_manager
    }

    #[view]
    public fun get_fee_collector(): address acquires Roles {
        borrow_global<Roles>(@staking).fee_collector
    }

    #[view]
    public fun all_roles(): (address, address, address, address) acquires Roles {
        let roles = borrow_global<Roles>(@staking);
        (roles.pool_admin, roles.fee_manager, roles.reward_manager, roles.fee_collector)
    }
}