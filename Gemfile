# frozen_string_literal: true

source 'https://rubygems.org'

ruby '~> 3.4'

gem 'connection_pool',   '~> 2.4'
gem 'dry-validation',    '~> 1.10'
gem 'httpx',             '~> 1.3'
gem 'iodine',            '~> 0.7'
gem 'jwt',               '~> 2.8'
gem 'oj',                '~> 3.17'
gem 'pg',                '~> 1.5'
gem 'prometheus-client', '~> 4.2'
gem 'rack-attack',       '~> 6.7'
gem 'redis',             '~> 5.0'
gem 'redlock',           '~> 1.3'
gem 'roda',              '~> 3.103'
gem 'sequel',            '~> 5.75'
gem 'sequel_pg',         '~> 1.17'
gem 'sidekiq',           '~> 7.1'

gem 'rack-cors',         '~> 2.0'

gem 'dotenv', '~> 3.1', groups: %i[development test]

group :development, :test do
  gem 'brakeman', require: false
  gem 'bundler-audit', require: false
  gem 'database_cleaner-sequel'
  gem 'pry'
  gem 'rack-test'
  gem 'rspec'
  gem 'webmock'
end
