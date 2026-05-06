Sequel.migration do
  change do
    create_table(:propay_subscriptions) do
      primary_key :id, type: :Bignum
      foreign_key :customer_id, :propay_customers, type: :Bignum, null: false
      String  :plan_name,           null: false
      String  :status,              null: false, default: 'trialing'
      Integer :amount_cents,        null: false
      String  :interval,            null: false
      column  :trial_ends_at,        'timestamptz'
      column  :current_period_start, 'timestamptz'
      column  :current_period_end,   'timestamptz'
      column  :next_charge_at,       'timestamptz'
      Integer :payment_failures, null: false, default: 0
      String  :id_rec, unique: true
      column  :cancelled_at, 'timestamptz'
      column  :ends_at,      'timestamptz'
      column  :created_at, 'timestamptz', null: false, default: Sequel.lit('NOW()')
      column  :updated_at, 'timestamptz', null: false, default: Sequel.lit('NOW()')

      index [:status, :next_charge_at]
      index :customer_id
    end
  end
end
