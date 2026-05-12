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

retries    = Integer(ENV.fetch('DB_CONNECT_RETRIES', '10'))
retry_wait = Integer(ENV.fetch('DB_CONNECT_RETRY_DELAY', '3'))

begin
  DB = Sequel.connect(**db_opts)
rescue Sequel::DatabaseConnectionError => e
  raise if retries.zero?

  retries -= 1
  warn "DB not ready (#{e.message.lines.first&.chomp}), retrying in #{retry_wait}s... (#{retries} left)"
  sleep retry_wait
  retry
end

require 'sequel_pg'
DB.extension :pg_json
DB.freeze
