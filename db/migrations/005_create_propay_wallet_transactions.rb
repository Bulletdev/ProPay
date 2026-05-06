Sequel.migration do
  change do
    create_table(:propay_wallet_transactions) do
      primary_key :id, type: :Bignum
      foreign_key :wallet_id, :propay_wallets, type: :Bignum, null: false
      Integer :amount_cents,  null: false
      String  :type,          null: false
      String  :reference_type
      Bignum  :reference_id
      String  :description,   null: false
      Integer :balance_after, null: false
      String  :idempotency_key, unique: true
      column  :created_at, 'timestamptz', null: false, default: Sequel.lit('NOW()')

      index [:wallet_id, :created_at]
    end
  end
end
