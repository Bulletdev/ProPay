Sequel.migration do
  change do
    create_table(:propay_charges) do
      primary_key :id, type: :Bignum
      foreign_key :customer_id, :propay_customers, type: :Bignum, null: false
      Bignum  :subscription_id
      String  :txid,            size: 35, null: false, unique: true
      String  :provider,        null: false
      String  :provider_id
      Integer :amount_cents,    null: false
      String  :status,          null: false, default: 'pending'
      column  :qr_code, :text
      String  :qr_code_url
      String  :end_to_end_id,   unique: true
      String  :reference_type
      Bignum  :reference_id
      column  :expires_at, 'timestamptz', null: false
      column  :paid_at,    'timestamptz'
      String  :idempotency_key, unique: true
      column  :metadata, :jsonb, default: Sequel.lit("'{}'::jsonb")
      column  :created_at, 'timestamptz', null: false, default: Sequel.lit('NOW()')
      column  :updated_at, 'timestamptz', null: false, default: Sequel.lit('NOW()')

      constraint(:positive_amount) { amount_cents > 0 }

      index :status
      index [:reference_type, :reference_id]
      index [:customer_id, :created_at]
    end
  end
end
