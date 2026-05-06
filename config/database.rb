# frozen_string_literal: true

require 'sequel'

db_opts = {
  adapter:         :postgres,
  host:            ENV.fetch('DB_HOST',     'propay-db'),
  port:            ENV.fetch('DB_PORT',     '5432').to_i,
  database:        ENV.fetch('DB_NAME',     'propay_development'),
  user:            ENV.fetch('DB_USER',     'propay'),
  password:        ENV.fetch('DB_PASSWORD', 'propay_dev_password'),
  max_connections: Integer(ENV.fetch('DB_POOL', '10')),
  pool_timeout:    5
}
db_opts[:logger] = Logger.new($stdout) if ENV['DB_LOGGING'] == 'true'

DB = Sequel.connect(**db_opts)
require 'sequel_pg'
DB.extension :pg_json
DB.freeze
