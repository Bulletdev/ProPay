# frozen_string_literal: true

require 'sequel'
require 'sequel_pg'

db_opts = {
  max_connections: Integer(ENV.fetch('DB_POOL', 10)),
  pool_timeout: 5
}
db_opts[:logger] = Logger.new($stdout) if ENV['DB_LOGGING'] == 'true'

DB = Sequel.connect(ENV.fetch('DATABASE_URL'), **db_opts)
DB.extension :pg_json
DB.freeze
