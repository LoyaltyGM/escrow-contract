/*
    Escrow is a contract between two parties, where one party (the creator) deposits items and/or SUI
    and the other party (the recipient) deposits items and/or SUI.
    Items must be of type T
*/
module holasui::escrow {
    use std::string::{utf8, String};
    use std::vector;

    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::dynamic_object_field as dof;
    use sui::event::emit;
    use sui::object::{Self, ID, UID};
    use sui::package;
    use sui::pay;
    use sui::sui::SUI;
    use sui::transfer::{share_object, public_transfer};
    use sui::tx_context::{TxContext, sender};
    use sui::vec_set;

    // ======== Constants =========
    const VERSION: u64 = 0;

    const STATUS_CANCELED: u8 = 0;
    const STATUS_ACTIVE: u8 = 1;
    const STATUS_EXCHANGED: u8 = 2;


    // ======== Errors =========

    const EWrongCreator: u64 = 0;
    const EWrongRecipient: u64 = 1;
    const EWrongItem: u64 = 2;
    const EWrongCoinAmount: u64 = 3;
    const EInvalidEscrow: u64 = 4;
    const EInactiveEscrow: u64 = 5;
    const EInsufficientPay: u64 = 6;
    const EZeroBalance: u64 = 7;
    const EWrongVersion: u64 = 8;
    const ENotUpgrade: u64 = 9;

    // ======== Types =========

    struct ESCROW has drop {}

    struct AdminCap has key, store {
        id: UID,
    }

    struct EscrowHub has key {
        id: UID,
        version: u64,
        fee: u64,
        balance: Balance<SUI>

        // dof
        // [id] -> Escrow
    }

    /// Struct that represents an Escrow
    struct Escrow<phantom T: key + store> has key, store {
        id: UID,
        status: u8,
        //
        creator: address,
        creator_items_ids: vector<ID>,
        creator_coin_amount: u64,
        //
        recipient: address,
        recipient_items_ids: vector<ID>,
        recipient_coin_amount: u64,
    }

    // ======== Events =========

    struct EscrowCreated has copy, drop {
        id: ID,
    }

    struct EscrowCanceled has copy, drop {
        id: ID,
    }

    struct EscrowExchanged has copy, drop {
        id: ID,
    }

    // ======== Functions =========

    fun init(otw: ESCROW, ctx: &mut TxContext) {
        public_transfer(package::claim(otw, ctx), sender(ctx));

        public_transfer(AdminCap {
            id: object::new(ctx)
        }, sender(ctx));

        share_object(EscrowHub {
            id: object::new(ctx),
            version: VERSION,
            fee: 400000000,
            balance: balance::zero()
        })
    }

    // ======== Admin functions ========

    entry fun update_fee(_: &AdminCap, hub: &mut EscrowHub, fee: u64) {
        hub.fee = fee;
    }

    entry fun withdraw(_: &AdminCap, hub: &mut EscrowHub, ctx: &mut TxContext) {
        let amount = balance::value(&hub.balance);
        assert!(amount > 0, EZeroBalance);

        pay::keep(coin::take(&mut hub.balance, amount, ctx), ctx);
    }

    entry fun migrate_hub(_: &AdminCap, hub: &mut EscrowHub) {
        assert!(hub.version < VERSION, ENotUpgrade);

        hub.version = VERSION;
    }

    // ======== Creator of Escrow functions ========

    /*
        Creates an Escrow with the given items and coin.
        The creator of the Escrow is the sender of the transaction.
        The recipient of the Escrow is the given recipient.
        The creator of the Escrow can cancel it at any time.
        The recipient of the Escrow can exchange it at any time.
    */
    entry fun create<T: key + store>(
        hub: &mut EscrowHub,
        creator_items: vector<T>,
        creator_coin: Coin<SUI>,
        recipient: address,
        recipient_items_ids: vector<ID>,
        recipient_coin_amount: u64,
        ctx: &mut TxContext
    ) {
        check_hub_version(hub);

        assert!(recipient != sender(ctx), EWrongRecipient);
        assert!(vector::length(&creator_items) > 0 || vector::length(&recipient_items_ids) > 0, EInvalidEscrow);

        let id = object::new(ctx);

        let creator_items_ids = add_items_to_dof(&mut id, creator_items);
        let creator_coin_amount = add_coin_to_dof(&mut id, creator_coin);

        check_vector_for_duplicates(&recipient_items_ids);

        let escrow = Escrow<T> {
            id,
            status: STATUS_ACTIVE,
            creator: sender(ctx),
            creator_items_ids,
            creator_coin_amount,
            recipient,
            recipient_items_ids,
            recipient_coin_amount,
        };

        emit(EscrowCreated {
            id: object::id(&escrow)
        });

        dof::add<ID, Escrow<T>>(&mut hub.id, object::id(&escrow), escrow);
    }

    /*
        Cancels an Escrow.
        The sender of the transaction must be the creator of the Escrow.
        The Escrow must be active.
    */
    entry fun cancel<T: key + store>(
        hub: &mut EscrowHub,
        escrow_id: ID,
        ctx: &mut TxContext
    ) {
        check_hub_version(hub);

        let escrow = dof::borrow_mut<ID, Escrow<T>>(&mut hub.id, escrow_id);

        assert!(escrow.status == STATUS_ACTIVE, EInactiveEscrow);
        assert!(sender(ctx) == escrow.creator, EWrongCreator);

        emit(EscrowCanceled {
            id: object::id(escrow)
        });

        escrow.status = STATUS_CANCELED;
        transfer_items(get_items_from_dof<T>(&mut escrow.id, *&escrow.creator_items_ids), sender(ctx));
        public_transfer(get_coin_from_dof(&mut escrow.id),  sender(ctx));
    }


    // ======== Recipient of Escrow functions ========

    /*
        Exchanges an Escrow.
        The sender of the transaction must be the recipient of the Escrow.
        The Escrow must be active.
        The recipient of the Escrow must have the given items.
        The recipient of the Escrow must have the given coin.
    */
    entry fun exchange<T: key + store>(
        hub: &mut EscrowHub,
        fee_coin: Coin<SUI>,
        escrow_id: ID,
        recipient_items: vector<T>,
        recipient_coin: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        check_hub_version(hub);

        assert!(coin::value(&fee_coin) == hub.fee, EInsufficientPay);
        coin::put(&mut hub.balance, fee_coin);

        let escrow = dof::borrow_mut<ID, Escrow<T>>(&mut hub.id, escrow_id);

        assert!(escrow.status == STATUS_ACTIVE, EInactiveEscrow);
        assert!(sender(ctx) == escrow.recipient, EWrongRecipient);
        assert!(coin::value(&recipient_coin) == escrow.recipient_coin_amount, EWrongCoinAmount);
        check_items_ids(&recipient_items, &escrow.recipient_items_ids);

        emit(EscrowExchanged {
            id: object::id(escrow)
        });

        escrow.status = STATUS_EXCHANGED;

        // transfer creator itemss to recipient
        transfer_items(get_items_from_dof<T>(&mut escrow.id, *&escrow.creator_items_ids), sender(ctx));
        public_transfer(get_coin_from_dof(&mut escrow.id), sender(ctx));

        // transfer recipient items to creator
        transfer_items(recipient_items, escrow.creator);
        public_transfer(recipient_coin, escrow.creator);
    }

    // ======== Utility functions =========

    fun check_hub_version(hub: &EscrowHub) {
        assert!(hub.version == VERSION, EWrongVersion);
    }

    /*
        Adds the given items to dynamic fields of given UID.
        Returns the IDs of the added items.
    */
    fun add_items_to_dof<T: key + store>(
        uid: &mut UID,
        items: vector<T>
    ): vector<ID> {
        let items_ids = vector::empty<ID>();

        while (!vector::is_empty(&items)) {
            let item = vector::pop_back(&mut items);
            let item_id = object::id(&item);

            dof::add(uid, item_id, item);
            vector::push_back(&mut items_ids, item_id);
        };
        vector::destroy_empty(items);

        items_ids
    }

    /*
        Removes the given items from dynamic fields of given UID.
        Transfers the removed items to the given address.
    */
    fun get_items_from_dof<T: key + store>(
        uid: &mut UID,
        items_ids: vector<ID>,
    ): vector<T> {
        let items = vector::empty<T>();

        while (!vector::is_empty(&items_ids)) {
            let item_id = vector::pop_back(&mut items_ids);
            let item = dof::remove<ID, T>(uid, item_id);

            vector::push_back(&mut items, item);
        };
        vector::destroy_empty(items_ids);

        items
    }

    /*
        Adds the given coin to dynamic fields of given UID.
        Returns the value of the added coin.
    */
    fun add_coin_to_dof(
        uid: &mut UID,
        coin: Coin<SUI>
    ): u64 {
        let value = coin::value(&coin);
        dof::add(uid, utf8(b"escrowed_coin"), coin);
        value
    }

    /*
        Removes the given coin from dynamic fields of given UID.
        Transfers the removed coin to the given address.
    */
    fun get_coin_from_dof(
        uid: &mut UID,
    ): Coin<SUI> {
        dof::remove<String, Coin<SUI>>(uid, utf8(b"escrowed_coin"))
    }

    fun transfer_items<T: key + store>(
        items: vector<T>,
        to: address
    ) {
        while (!vector::is_empty(&items)) {
            let item = vector::pop_back(&mut items);
            public_transfer(item, to);
        };
        vector::destroy_empty(items);
    }

    fun check_items_ids<T: key + store>(
        items: &vector<T>,
        ids: &vector<ID>
    ) {
        assert!(vector::length(items) == vector::length(ids), EWrongItem);

        let i = 0;
        while (i < vector::length(items)) {
            assert!(
                vector::contains(ids,&object::id(vector::borrow(items, i))),
                EWrongItem
            );
            i = i + 1;
        };
    }

    /*
        Checks if the given vector contains unique items.
        Aborts if there are duplicates.
    */
    fun check_vector_for_duplicates<T: copy + drop>(
        items: &vector<T>
    ) {
        let set = vec_set::empty<T>();

        let i = 0;
        while (i < vector::length(items)) {
            vec_set::insert(&mut set, *vector::borrow(items, i));
            i = i + 1;
        };
    }
}
