# frozen_string_literal: true

# prostaff-api uses UUID strings for user IDs.
# These columns were originally bigint, causing PG::InvalidTextRepresentation
# whenever the JWT user_id (UUID) was used for lookups.
Sequel.migration do
  up do
    # propay_wallets.user_id: bigint → text
    run 'ALTER TABLE propay_wallets DROP CONSTRAINT IF EXISTS propay_wallets_user_id_key'
    run 'DROP INDEX IF EXISTS propay_wallets_user_id_index'
    run 'ALTER TABLE propay_wallets ALTER COLUMN user_id TYPE text USING user_id::text'
    run 'ALTER TABLE propay_wallets ADD CONSTRAINT propay_wallets_user_id_key UNIQUE (user_id)'
    run 'CREATE INDEX propay_wallets_user_id_index ON propay_wallets (user_id)'

    # propay_customers.owner_id: bigint → text
    run 'ALTER TABLE propay_customers DROP CONSTRAINT IF EXISTS propay_customers_owner_type_owner_id_key'
    run 'ALTER TABLE propay_customers ALTER COLUMN owner_id TYPE text USING owner_id::text'
    run 'ALTER TABLE propay_customers ADD CONSTRAINT propay_customers_owner_type_owner_id_key UNIQUE (owner_type, owner_id)'

    # propay_charges.reference_id: bigint → text (nullable, receives user UUID on deposit)
    run 'DROP INDEX IF EXISTS propay_charges_reference_type_reference_id_index'
    run 'ALTER TABLE propay_charges ALTER COLUMN reference_id TYPE text USING reference_id::text'
    run 'CREATE INDEX propay_charges_reference_type_reference_id_index ON propay_charges (reference_type, reference_id)'

    # propay_wallet_transactions.reference_id: bigint → text (nullable, mirrors charges)
    run 'ALTER TABLE propay_wallet_transactions ALTER COLUMN reference_id TYPE text USING reference_id::text'
  end

  down do
    raise Sequel::Error, 'Cannot revert: UUID strings stored in these columns cannot be safely cast back to bigint'
  end
end
