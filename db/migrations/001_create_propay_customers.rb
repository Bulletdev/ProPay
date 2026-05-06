Sequel.migration do
  change do
    create_table(:propay_customers) do
      primary_key :id, type: :Bignum
      String  :owner_type, null: false
      Bignum  :owner_id,   null: false
      String  :cpf,        size: 11
      String  :full_name,  null: false
      String  :email,      null: false
      column  :provider_data, :jsonb, default: Sequel.lit("'{}'::jsonb")
      column  :created_at, 'timestamptz', null: false, default: Sequel.lit('NOW()')

      unique [:owner_type, :owner_id]
      index  :email
    end
  end
end
