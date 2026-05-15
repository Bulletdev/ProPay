# frozen_string_literal: true

require 'dotenv/load'
require 'rspec'
require 'rack/test'
require 'webmock/rspec'
require 'database_cleaner/sequel'

ENV['DATABASE_URL']              ||= 'postgresql://propay:propay_test@localhost:5432/propay_test'
ENV['REDIS_URL']                 ||= 'redis://localhost:6379/9'
ENV['INTERNAL_JWT_SECRET']       ||= 'test_secret'
ENV['PROPAY_OPENPIX_APP_ID']     ||= 'test_openpix_app_id'
ENV['PROPAY_OPENPIX_SECRET']     ||= 'test_openpix_secret'
ENV['PROPAY_OPENPIX_SECRET_PREV'] ||= ''
ENV['PROPAY_PROVIDER']           ||= 'openpix'
ENV['PROSTAFF_API_URL']          ||= 'http://prostaff-api:3000'

PROPAY_VERSION  = '1.0.0' unless defined?(PROPAY_VERSION)
SUPPORTED_PLANS = %w[pro_monthly pro_annual enterprise].freeze unless defined?(SUPPORTED_PLANS)
PIX_KEY_TYPES   = %w[cpf cnpj email phone random].freeze unless defined?(PIX_KEY_TYPES)
VALID_PROVIDERS = %w[openpix efi].freeze unless defined?(VALID_PROVIDERS)

require 'sequel'
require 'oj'
require 'jwt'
require 'redis'
require 'connection_pool'
require 'redlock'

DB = Sequel.connect(ENV.fetch('DATABASE_URL'), max_connections: 1) unless defined?(DB)
require 'sequel_pg'
DB.extension :pg_json
DB.extension :pg_array

unless defined?(REDIS_POOL)
  REDIS_POOL = ConnectionPool.new(size: 2, timeout: 2) do
    Redis.new(url: ENV.fetch('REDIS_URL'))
  end
end

REDLOCK_CLIENT = Redlock::Client.new([ENV.fetch('REDIS_URL')]) unless defined?(REDLOCK_CLIENT)

Dir[File.join(__dir__, '..', 'app', 'models',     '*.rb')].each { |f| require f }
Dir[File.join(__dir__, '..', 'app', 'middleware', '*.rb')].each { |f| require f }
Dir[File.join(__dir__, '..', 'app', 'providers',  '*.rb')].each { |f| require f }
Dir[File.join(__dir__, '..', 'app', 'validators', '*.rb')].each { |f| require f }
Dir[File.join(__dir__, '..', 'app', 'services',   '*.rb')].each { |f| require f }
Dir[File.join(__dir__, '..', 'app', 'jobs',       '*.rb')].each { |f| require f }
Dir[File.join(__dir__, '..', 'app', 'handlers',   '*.rb')].each { |f| require f }
require_relative '../app/propay_app'

WebMock.disable_net_connect!(allow_localhost: true)

RSpec::Matchers.define :be_present do
  match { |actual| !actual.nil? && actual != '' && actual != [] && actual != {} }
  description { 'be present (not nil/blank)' }
end

def not_change(&)
  change(&).by(0)
end

RSpec.configure do |config|
  config.include Rack::Test::Methods

  config.before(:suite) do
    DatabaseCleaner[:sequel].strategy = :transaction
    DatabaseCleaner[:sequel].clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner[:sequel].cleaning { example.run }
  end

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end

def app
  ProPayApp.freeze.app
end

def jwt_token(user_id: 1, role: 'member')
  payload = { 'user_id' => user_id, 'role' => role, 'exp' => Time.now.to_i + 3600 }
  JWT.encode(payload, ENV.fetch('INTERNAL_JWT_SECRET'), 'HS256')
end

def auth_header(user_id: 1, role: 'member')
  { 'HTTP_AUTHORIZATION' => "Bearer #{jwt_token(user_id: user_id, role: role)}" }
end

def json_body
  Oj.load(last_response.body, mode: :compat)
end

def create_customer(owner_id: 1, owner_type: 'user', email: 'test@propay.gg', full_name: 'Test User')
  Customer.create(owner_type: owner_type, owner_id: owner_id, full_name: full_name, email: email)
end

def create_wallet(user_id: 1, balance_cents: 0)
  Wallet.create(user_id: user_id, balance_cents: balance_cents)
end
