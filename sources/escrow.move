/*
    Escrow is a contract between two parties, where one party (the creator) deposits items and/or SUI
    and the other party (the recipient) deposits items and/or SUI.
    Items must be of type T
*/
module holasui::escrow {
    use std::option::{Self, Option};
    use std::vector;

    use sui::coin::{Self, Coin};
    use sui::dynamic_object_field as dof;
    use sui::event::emit;
    use sui::object::{Self, ID, UID};
    use sui::package;
    use sui::sui::SUI;
    use sui::transfer::{share_object, public_transfer};
    use sui::tx_context::{TxContext, sender};

    // ======== Constants =========

    const STATUS_CANCELED: u8 = 0;
    const STATUS_ACTIVE: u8 = 1;
    const STATUS_EXCHANGED: u8 = 2;


    // ======== Errors =========

    const EWrongOwner: u64 = 0;
    const EWrongRecipient: u64 = 1;
    const EWrongItem: u64 = 2;
    const EWrongCoinAmount: u64 = 3;
    const EInvalidEscrow: u64 = 4;
    const EInactiveEscrow: u64 = 5;

    // ======== Types =========

    struct ESCROW has drop {}

    struct EscrowHub has key {
        id: UID,

        // dof
        // [id] -> Escrow
    }

    /// Struct that represents an Escrow
    struct Escrow<T: key + store> has key, store {
        id: UID,
        status: u8,
        //
        creator: address,
        creator_items: Option<vector<T>>,
        creator_coin: Option<Coin<SUI>>,
        //
        recipient: address,
        recipient_items_ids: vector<ID>,
        recipient_coin_amount: u64,
    }

    // ======== Events =========

    struct Created has copy, drop {
        escrow_id: ID,
    }

    struct Canceled has copy, drop {
        escrow_id: ID,
    }

    struct Exchanged has copy, drop {
        escrow_id: ID,
    }

    // ======== Functions =========

    fun init(otw: ESCROW, ctx: &mut TxContext) {
        let publisher = package::claim(otw, ctx);

        public_transfer(publisher, sender(ctx));
        share_object(EscrowHub {
            id: object::new(ctx),
        })
    }

    // ======== Creator of Escrow functions ========

    /*
        Creates an Escrow with the given items and coin.
        The creator of the Escrow is the sender of the transaction.
        The recipient of the Escrow is the given recipient.
        The creator of the Escrow can cancel it at any time.
        The recipient of the Escrow can exchange it at any time.
    */
    public fun create<T: key + store>(
        hub: &mut EscrowHub,
        creator_items: vector<T>,
        creator_coin: Coin<SUI>,
        recipient: address,
        recipient_items_ids: vector<ID>,
        recipient_coin_amount: u64,
        ctx: &mut TxContext
    ) {
        assert!(recipient != sender(ctx), EWrongRecipient);
        assert!(vector::length(&creator_items) > 0 || vector::length(&recipient_items_ids) > 0, EInvalidEscrow);

        let escrow = Escrow<T> {
            id: object::new(ctx),
            status: STATUS_ACTIVE,
            creator: sender(ctx),
            creator_items: option::some(creator_items),
            creator_coin: option::some(creator_coin),
            recipient,
            recipient_items_ids,
            recipient_coin_amount,
        };

        emit(Created {
            escrow_id: object::id(&escrow)
        });

        dof::add<ID, Escrow<T>>(&mut hub.id, object::id(&escrow), escrow);
    }

    /*
        Cancels an Escrow.
        The sender of the transaction must be the creator of the Escrow.
        The Escrow must be active.
    */
    public fun cancel_creator_escrow<T: key + store>(
        hub: &mut EscrowHub,
        escrow_id: ID,
        ctx: &mut TxContext
    ) {
        let escrow = dof::borrow_mut<ID, Escrow<T>>(&mut hub.id, escrow_id);

        assert!(escrow.status == STATUS_ACTIVE, EInactiveEscrow);
        assert!(sender(ctx) == escrow.creator, EWrongOwner);

        emit(Canceled {
            escrow_id: object::id(escrow)
        });

        escrow.status = STATUS_CANCELED;
        transfer_items(option::extract(&mut escrow.creator_items), sender(ctx));
        public_transfer(option::extract(&mut escrow.creator_coin), sender(ctx));
    }


    // ======== Recipient of Escrow functions ========

    /*
        Exchanges an Escrow.
        The sender of the transaction must be the recipient of the Escrow.
        The Escrow must be active.
        The recipient of the Escrow must have the given items.
        The recipient of the Escrow must have the given coin.
    */
    public fun exchange<T: key + store>(
        hub: &mut EscrowHub,
        escrow_id: ID,
        recipient_items: vector<T>,
        recipient_coin: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let escrow = dof::borrow_mut<ID, Escrow<T>>(&mut hub.id, escrow_id);

        assert!(escrow.status == STATUS_ACTIVE, EInactiveEscrow);
        assert!(sender(ctx) == escrow.recipient, EWrongRecipient);
        assert!(coin::value(&recipient_coin) == escrow.recipient_coin_amount, EWrongCoinAmount);
        check_items_ids(&recipient_items, &escrow.recipient_items_ids);

        emit(Exchanged {
            escrow_id: object::id(escrow)
        });

        escrow.status = STATUS_EXCHANGED;

        // transfer creator itemss to recipient
        transfer_items(option::extract(&mut escrow.creator_items), sender(ctx));
        public_transfer(option::extract(&mut escrow.creator_coin), sender(ctx));

        // transfer recipient items to creator
        transfer_items(recipient_items, escrow.creator);
        public_transfer(recipient_coin, escrow.creator);
    }

    // ======== Utility functions =========

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
        while (i < vector::length(ids)) {
            assert!(
                vector::contains(ids,&object::id(vector::borrow(items, i))),
                EWrongItem
            );
            i = i + 1;
        };
    }
}
