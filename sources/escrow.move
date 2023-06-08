module holasui::escrow {
    use std::string::{utf8, String};
    use std::vector;

    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::dynamic_object_field as dof;
    use sui::event::emit;
    use sui::object::{Self, ID, UID};
    use sui::object_bag::{Self, ObjectBag};
    use sui::package;
    use sui::pay;
    use sui::sui::SUI;
    use sui::transfer::{share_object, public_transfer};
    use sui::tx_context::{TxContext, sender};

    // ======== Constants =========


    // ======== Errors =========
    const EWrongOwner: u64 = 0;
    const EWrongRecipient: u64 = 1;
    const EWrongObject: u64 = 2;
    const EWrongCoinAmount: u64 = 3;
    const EInvalidEscrow: u64 = 4;
    const EInactiveEscrow: u64 = 5;
    const EInsufficientPay: u64 = 6;
    const EZeroBalance: u64 = 7;

    // ======== Types =========
    struct ESCROW has drop {}

    struct AdminCap has key, store {
        id: UID,
    }

    struct EscrowHub has key {
        id: UID,
        fee: u64,
        balance: Balance<SUI>

        // dof
        // [id] -> Escrow
    }

    /// An object held in escrow
    struct Escrow<phantom T> has key, store {
        id: UID,
        active: bool,
        exchanged: bool,
        bag: ObjectBag,
        //
        creator: address,
        creator_object_ids: vector<ID>,
        creator_coin_amount: u64,
        //
        recipient: address,
        recipient_object_ids: vector<ID>,
        recipient_coin_amount: u64,
    }

    // ======== Events =========

    struct Created has copy, drop {
        escrow_id: ID,
    }

    struct Exchanged has copy, drop {
        escrow_id: ID,
    }

    // ======== Functions =========

    fun init(otw: ESCROW, ctx: &mut TxContext) {
        let publisher = package::claim(otw, ctx);

        public_transfer(publisher, sender(ctx));
        public_transfer(AdminCap { id: object::new(ctx) }, sender(ctx));
        share_object(EscrowHub {
            id: object::new(ctx),
            fee: 400000000,
            balance: balance::zero()
        })
    }

    // ======== Admin functions ========

    entry fun set_fee(_: &AdminCap, hub: &mut EscrowHub, fee: u64) {
        hub.fee = fee;
    }

    entry fun withdraw(_: &AdminCap, hub: &mut EscrowHub, ctx: &mut TxContext) {
        let amount = balance::value(&hub.balance);
        assert!(amount > 0, EZeroBalance);

        pay::keep(coin::take(&mut hub.balance, amount, ctx), ctx);
    }


    // ======== Creator of Escrow functions ========

    public fun create<T>(
        creator_object_ids: vector<ID>,
        creator_coin_amount: u64,
        recipient: address,
        recipient_object_ids: vector<ID>,
        recipient_coin_amount: u64,
        ctx: &mut TxContext
    ): Escrow<T> {
        assert!(recipient != sender(ctx), EWrongRecipient);
        assert!(vector::length(&creator_object_ids) > 0 || vector::length(&recipient_object_ids) > 0, EInvalidEscrow);

        Escrow {
            id: object::new(ctx),
            active: false,
            exchanged: false,
            bag: object_bag::new(ctx),
            creator: sender(ctx),
            creator_object_ids,
            creator_coin_amount,
            recipient,
            recipient_object_ids,
            recipient_coin_amount,
        }
    }

    public fun update_creator_objects<T: key + store>(
        escrow: Escrow<T>,
        item: T,
        ctx: &mut TxContext
    ): Escrow<T> {
        assert!(!escrow.active, EInactiveEscrow);
        assert!(sender(ctx) == escrow.creator, EWrongOwner);

        assert!(vector::contains(&escrow.creator_object_ids, &object::id(&item)), EWrongObject);

        object_bag::add<ID, T>(&mut escrow.bag, object::id(&item), item);

        escrow
    }

    public fun update_creator_coin<T>(
        escrow: Escrow<T>,
        coin: Coin<SUI>,
        ctx: &mut TxContext
    ): Escrow<T> {
        assert!(!escrow.active, EInactiveEscrow);
        assert!(sender(ctx) == escrow.creator, EWrongOwner);

        assert!(coin::value(&coin) == escrow.creator_coin_amount, EWrongCoinAmount);

        object_bag::add<String, Coin<SUI>>(&mut escrow.bag, key_creator_coin(), coin);

        escrow
    }

    public fun share_escrow<T>(
        hub: &mut EscrowHub,
        escrow: Escrow<T>,
        ctx: &mut TxContext
    ) {
        assert!(!escrow.active, EInactiveEscrow);
        assert!(sender(ctx) == escrow.creator, EWrongOwner);

        check_creator_objects(&mut escrow);

        escrow.active = true;

        emit(Created {
            escrow_id: object::id(&escrow)
        });

        dof::add<ID, Escrow<T>>(&mut hub.id, object::id(&escrow), escrow);
    }

    public fun cancel_creator_escrow<T: key + store>(
        hub: &mut EscrowHub,
        escrow_id: ID,
        ctx: &mut TxContext
    ) {
        let escrow = dof::borrow_mut<ID, Escrow<T>>(&mut hub.id, escrow_id);

        assert!(escrow.active, EInactiveEscrow);
        assert!(sender(ctx) == escrow.creator, EWrongOwner);

        transfer_creator_objects(escrow, sender(ctx));

        escrow.active = false;
    }

    // ======== Recipient of Escrow functions ========

    public fun update_recipient_objects<T: key + store>(
        hub: &mut EscrowHub,
        escrow_id: ID,
        item: T,
        ctx: &mut TxContext
    ) {
        let escrow = dof::borrow_mut<ID, Escrow<T>>(&mut hub.id, escrow_id);

        assert!(escrow.active, EInactiveEscrow);
        assert!(sender(ctx) == escrow.recipient, EWrongRecipient);

        assert!(vector::contains(&escrow.recipient_object_ids, &object::id(&item)), EWrongObject);

        object_bag::add<ID, T>(&mut escrow.bag, object::id(&item), item);
    }

    public fun update_recipient_coin<T>(
        hub: &mut EscrowHub,
        escrow_id: ID,
        coin: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let escrow = dof::borrow_mut<ID, Escrow<T>>(&mut hub.id, escrow_id);

        assert!(escrow.active, EInactiveEscrow);
        assert!(sender(ctx) == escrow.recipient, EWrongRecipient);

        assert!(coin::value(&coin) == escrow.recipient_coin_amount, EWrongCoinAmount);

        object_bag::add<String, Coin<SUI>>(&mut escrow.bag, key_recipient_coin(), coin);
    }

    public fun cancel_recipient_escrow<T: key + store>(
        hub: &mut EscrowHub,
        escrow_id: ID,
        ctx: &mut TxContext
    ) {
        let escrow = dof::borrow_mut<ID, Escrow<T>>(&mut hub.id, escrow_id);

        assert!(sender(ctx) == escrow.recipient, EWrongRecipient);

        transfer_recipient_objects(escrow, sender(ctx));
    }

    public fun exchange<T: key + store>(
        hub: &mut EscrowHub,
        escrow_id: ID,
        fee_coin: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        assert!(coin::value(&fee_coin) == hub.fee, EInsufficientPay);
        coin::put(&mut hub.balance, fee_coin);

        let escrow = dof::borrow_mut<ID, Escrow<T>>(&mut hub.id, escrow_id);

        assert!(escrow.active, EInactiveEscrow);
        assert!(sender(ctx) == escrow.recipient, EWrongRecipient);

        check_creator_objects(escrow);
        check_recipient_objects(escrow);

        emit(Exchanged {
            escrow_id: object::id(escrow)
        });

        escrow.active = false;
        escrow.exchanged = true;

        let recipient = escrow.recipient;
        transfer_creator_objects(escrow, recipient);

        let creator = escrow.creator;
        transfer_recipient_objects(escrow, creator);
    }

    // ======== Utility functions =========

    fun key_creator_coin(): String {
        utf8(b"creator_coin")
    }

    fun key_recipient_coin(): String {
        utf8(b"recipient_coin")
    }

    fun check_creator_objects<T>(escrow: &mut Escrow<T>) {
        let i = 0;
        while (i < vector::length(&escrow.creator_object_ids)) {
            assert!(
                object_bag::contains<ID>(&escrow.bag, *vector::borrow(&escrow.creator_object_ids, i)),
                EInvalidEscrow
            );
            i = i + 1;
        };

        if (escrow.creator_coin_amount > 0) {
            assert!(
                coin::value(
                    object_bag::borrow<String, Coin<SUI>>(&escrow.bag, key_creator_coin())
                ) == escrow.creator_coin_amount,
                EInvalidEscrow
            );
        }
    }

    fun check_recipient_objects<T>(escrow: &mut Escrow<T>) {
        let i = 0;
        while (i < vector::length(&escrow.recipient_object_ids)) {
            assert!(
                object_bag::contains<ID>(&escrow.bag, *vector::borrow(&escrow.recipient_object_ids, i)),
                EInvalidEscrow
            );
            i = i + 1;
        };

        if (escrow.recipient_coin_amount > 0) {
            assert!(
                coin::value(
                    object_bag::borrow<String, Coin<SUI>>(&escrow.bag, key_recipient_coin())
                ) == escrow.recipient_coin_amount,
                EInvalidEscrow
            );
        }
    }

    fun transfer_creator_objects<T: key + store>(escrow: &mut Escrow<T>, to: address) {
        let i = 0;
        while (i < vector::length(&escrow.creator_object_ids)) {
            if (object_bag::contains<ID>(&escrow.bag, *vector::borrow(&escrow.creator_object_ids, i))) {
                let obj = object_bag::remove<ID, T>(
                    &mut escrow.bag,
                    *vector::borrow(&escrow.creator_object_ids, i)
                );
                public_transfer(obj, to);
            };
            i = i + 1;
        };

        if (object_bag::contains<String>(&escrow.bag, key_creator_coin())) {
            let coin = object_bag::remove<String, Coin<SUI>>(&mut escrow.bag, key_creator_coin());
            public_transfer(coin, to);
        };
    }

    fun transfer_recipient_objects<T: key + store>(escrow: &mut Escrow<T>, to: address) {
        let i = 0;
        while (i < vector::length(&escrow.recipient_object_ids)) {
            if (object_bag::contains<ID>(&escrow.bag, *vector::borrow(&escrow.recipient_object_ids, i))) {
                let obj = object_bag::remove<ID, T>(
                    &mut escrow.bag,
                    *vector::borrow(&escrow.recipient_object_ids, i)
                );
                public_transfer(obj, to);
            };
            i = i + 1;
        };

        if (object_bag::contains<String>(&escrow.bag, key_recipient_coin())) {
            let coin = object_bag::remove<String, Coin<SUI>>(&mut escrow.bag, key_recipient_coin());
            public_transfer(coin, to);
        };
    }
}
