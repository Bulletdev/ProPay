Sequel.migration do
  change do
    create_table(:propay_wallets) do
      primary_key :id, type: :Bignum
      Bignum  :user_id, null: false, unique: true
      Integer :balance_cents, null: false, default: 0
      column  :created_at, 'timestamptz', null: false, default: Sequel.lit('NOW()')
      column  :updated_at, 'timestamptz', null: false, default: Sequel.lit('NOW()')

      constraint(:non_negative_balance) { balance_cents >= 0 }

      index :user_id
    end
  end
end
