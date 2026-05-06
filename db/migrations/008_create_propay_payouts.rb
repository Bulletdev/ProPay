Sequel.migration do
  change do
    create_table(:propay_payouts) do
      primary_key :id, type: :Bignum
      foreign_key :wallet_id, :propay_wallets, type: :Bignum, null: false
      Integer :amount_cents, null: false
      String  :pix_key,      null: false
      String  :pix_key_type, null: false
      String  :status,       null: false, default: 'pending'
      String  :provider_transfer_id
      column  :completed_at,   'timestamptz'
      column  :failed_at,      'timestamptz'
      column  :failure_reason, :text
      column  :created_at, 'timestamptz', null: false, default: Sequel.lit('NOW()')

      constraint(:positive_payout) { amount_cents > 0 }

      index :wallet_id
      index :status
    end
  end
end
