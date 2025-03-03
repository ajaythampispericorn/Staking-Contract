module staking::mycoin {
    use std::string;
    use std::signer;
    use aptos_framework::coin;
    use aptos_framework::coin::{BurnCapability, FreezeCapability, MintCapability};

    struct MyCoin has key, store {}

    // Keep all capabilities in one struct
    struct Capabilities has key {
        burn_cap: BurnCapability<MyCoin>,
        freeze_cap: FreezeCapability<MyCoin>,
        mint_cap: MintCapability<MyCoin>
    }

    // Initialize function should only be called once by admin
    public fun initialize(admin: &signer) {
        // Check that the admin is the module owner
        assert!(signer::address_of(admin) == @staking, 1);

        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<MyCoin>(
            admin,
            string::utf8(b"MyCoin"),
            string::utf8(b"MC"),
            6,
            true
        );

        // Register admin account to receive initial coins
        coin::register<MyCoin>(admin);

        // Mint initial supply
        let coins = coin::mint<MyCoin>(1_000_000_000_000, &mint_cap);
        coin::deposit(signer::address_of(admin), coins);

        // Store capabilities
        move_to(admin, Capabilities {
            burn_cap,
            freeze_cap,
            mint_cap
        });
    }

    public fun register(account: &signer) {
        coin::register<MyCoin>(account);
    }

    public entry fun mint_coins(admin: &signer, amount: u64) acquires Capabilities {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @staking, 1);

        let capabilities = borrow_global<Capabilities>(@staking);
        let coins = coin::mint<MyCoin>(amount, &capabilities.mint_cap);
        coin::deposit(admin_addr, coins);
    }

    public entry fun transfer(from: &signer, to: address, amount: u64) {
        coin::transfer<MyCoin>(from, to, amount);
    }

    #[view]
    public fun balance(owner: address): u64 {
        if (coin::is_account_registered<MyCoin>(owner)) {
            coin::balance<MyCoin>(owner)
        } else {
            0
        }
    }
}