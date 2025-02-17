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
        let coins = coin::mint<MyCoin>(1_000_000, &mint_cap);
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
}