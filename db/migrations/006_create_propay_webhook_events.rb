Sequel.migration do
  change do
    create_table(:propay_webhook_events) do
      primary_key :id, type: :Bignum
      String  :provider,        null: false
      String  :event_type,      null: false
      String  :idempotency_key, null: false, unique: true
      String  :status,          null: false, default: 'pending'
      column  :payload, :jsonb, null: false
      column  :processed_at, 'timestamptz'
      column  :error_message, :text
      Integer :attempts, null: false, default: 0
      column  :created_at, 'timestamptz', null: false, default: Sequel.lit('NOW()')

      index [:status, :created_at]
    end
  end
end
