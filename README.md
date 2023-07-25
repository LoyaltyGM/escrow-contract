# Escrow contract
# Introduction

Escrow Smart Contract is a cutting-edge, decentralized, and trustless solution that revolutionizes the way individuals engage in peer-to-peer (P2P) exchanges, ensuring the security and transparency of each transaction. Built on the sui blockchain, this smart contract introduces a versatile and adaptable escrow mechanism, allowing for seamless 1-to-1, 1-to-many, and many-to-many exchanges of sui objects.

It is a contract between two parties, where one party (the creator) deposits items and/or a specified token (SUI), and the other party (the recipient) deposits items and/or a specified amount of SUI. The items deposited must be of type T.

# Documentation

## Constants

- `VERSION`: The current version of the Escrow smart contract.
- `STATUS_CANCELED`: Represents the status of a canceled Escrow.
- `STATUS_ACTIVE`: Represents the status of an active Escrow.
- `STATUS_EXCHANGED`: Represents the status of an exchanged Escrow.

## Errors

The following error codes can be thrown during the execution of the smart contract functions:

- `EWrongCreator`: The transaction sender is not the creator of the Escrow.
- `EWrongRecipient`: The transaction sender is not the recipient of the Escrow.
- `EWrongItem`: The provided items do not match the Escrow requirements.
- `EWrongCoinAmount`: The provided amount of SUI does not match the Escrow requirements.
- `EInvalidEscrow`: The Escrow creation parameters are invalid.
- `EInactiveEscrow`: The Escrow is not active.
- `EInsufficientPay`: The required fee payment is insufficient.
- `EZeroBalance`: The EscrowHub balance is zero.
- `EWrongVersion`: The version of the EscrowHub does not match the current contract version.
- `ENotUpgrade`: An attempt to upgrade the EscrowHub to an invalid version.

## Types

- `ESCROW`: Represents the One Time Witness.
- `AdminCap`: Represents the administrative capability required for certain administrative functions.
- `EscrowHub`: Represents the EscrowHub instance, responsible for managing multiple Escrow instances.
- `Escrow`: Represents an individual Escrow instance.

## Events

- `EscrowCreated`: Event emitted when a new Escrow is created.
- `EscrowCanceled`: Event emitted when an Escrow is canceled.
- `EscrowExchanged`: Event emitted when an Escrow is exchanged.

## Initialization Functions

`init(otw: ESCROW, ctx: &mut TxContext)`

- `otw`: Represents the One Time Witness struct
- `ctx`: Represents the transaction context containing information about the current transaction.

Initializes the Escrow smart contract. This function should be called once during the deployment of the contract. It sets up the EscrowHub and initializes administrative capabilities.

## Admin Functions

`update_fee(admin_cap: &AdminCap, hub: &mut EscrowHub, fee: u64)`

- `admin_cap`: Represents the administrative capability required for certain administrative functions.
- `hub`: Represents the EscrowHub instance that will have its fee updated.
- `fee`: The new fee amount in SUI to be set for creating an Escrow.

Updates the fee for creating an Escrow. This function can only be called by an address with administrative capability (`admin_cap`). The `fee` parameter represents the new fee amount in SUI.  

<br>

`withdraw(admin_cap: &AdminCap, hub: &mut EscrowHub,ctx: &mut TxContext)`

- `admin_cap`: Represents the administrative capability required for certain administrative functions.
- `hub`: Represents the EscrowHub instance from which the accumulated fee balance will be withdrawn.
- `ctx`: Represents the transaction context containing information about the current transaction.

Withdraws the accumulated fee balance from the EscrowHub. This function can only be called by an address with administrative capability (`admin_cap`). The withdrawn amount will be sent to the caller's address.

<br>

`migrate_hub(admin_cap: &AdminCap, hub: &mut EscrowHub)`

- `admin_cap`: Represents the administrative capability required for certain administrative functions.
- `hub`: Represents the EscrowHub instance that will be migrated to the current contract version.

Migrates the EscrowHub to the current contract version. This function can only be called by an address with administrative capability (`admin_cap`). It updates the `version` of the EscrowHub to the current contract version.

## Escrow’s Creator Functions

`create<T: key + store>(hub: &mut EscrowHub, creator_items: vector<T>, creator_coin: Coin<SUI>, recipient: address, recipient_items_ids: vector<ID>, recipient_coin_amount: u64, ctx: &mut TxContext)`

- `hub`: Represents the EscrowHub instance where the new Escrow will be added.
- `creator_items`: A vector of items of type T deposited by the creator of the Escrow.
- `creator_coin`: The amount of SUI deposited by the creator of the Escrow.
- `recipient`: The address of the recipient of the Escrow.
- `recipient_items_ids`: A vector of IDs representing items that the recipient should deposit.
- `recipient_coin_amount`: The amount of SUI that the recipient should deposit.
- `ctx`: Represents the transaction context containing information about the current transaction.

Creates a new Escrow instance with the specified parameters. The caller of this function becomes the creator of the Escrow. The `creator_items` parameter is a vector of items of type T deposited by the creator. The `creator_coin` parameter is the amount of SUI deposited by the creator. The `recipient` parameter is the address of the recipient of the Escrow. The `recipient_items_ids` parameter is a vector of IDs representing items that the recipient should deposit. The `recipient_coin_amount` parameter is the amount of SUI that the recipient should deposit.

<br>

`cancel<T: key + store>(hub: &mut EscrowHub, escrow_id: ID, ctx: &mut TxContext)`

- `hub`: Represents the EscrowHub instance from which the Escrow will be canceled.
- `escrow_id`: The ID of the Escrow to be canceled.
- `ctx`: Represents the transaction context containing information about the current transaction.

Cancels an existing Escrow. This function can only be called by the creator of the Escrow. The `escrow_id` parameter specifies the ID of the Escrow to be canceled. The items and SUI deposited by the creator will be returned to them.

## Escrow’s Recipient Functions

`exchange<T: key + store>(hub: &mut EscrowHub, fee_coin: Coin<SUI>, escrow_id: ID, recipient_items: vector<T>, recipient_coin: Coin<SUI>, ctx: &mut TxContext)`

- `hub`: Represents the EscrowHub instance containing the Escrow to be exchanged.
- `fee_coin`: The amount of SUI paid as a fee for the exchange.
- `escrow_id`: The ID of the Escrow to be exchanged.
- `recipient_items`: A vector of items of type T deposited by the recipient for the exchange.
- `recipient_coin`: The amount of SUI deposited by the recipient for the exchange.
- `ctx`: Represents the transaction context containing information about the current transaction.

Exchanges an existing Escrow. This function can only be called by the recipient of the Escrow. The `escrow_id` parameter specifies the ID of the Escrow to be exchanged. The `fee_coin` parameter is the amount of SUI to pay as a fee for the exchange. The `recipient_items` parameter is a vector of items of type T deposited by the recipient. The `recipient_coin` parameter is the amount of SUI deposited by the recipient. Upon exchange, the items and SUI deposited by the recipient will be transferred to the creator of the Escrow, and the items and SUI deposited by the creator will be transferred to the recipient.