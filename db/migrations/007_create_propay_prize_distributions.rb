Sequel.migration do
  change do
    create_table(:propay_prize_distributions) do
      primary_key :id, type: :Bignum
      Bignum  :tournament_id,         null: false
      Integer :total_collected_cents, null: false
      Integer :platform_fee_cents,    null: false
      Integer :prize_pool_cents,      null: false
      String  :status, null: false, default: 'pending'
      column  :distributed_at, 'timestamptz'
      column  :entries, :jsonb, null: false, default: Sequel.lit("'[]'::jsonb")
      column  :created_at, 'timestamptz', null: false, default: Sequel.lit('NOW()')

      index :tournament_id
    end
  end
end
