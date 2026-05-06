# frozen_string_literal: true

require 'redis'
require 'connection_pool'
require 'redlock'

REDIS_POOL = ConnectionPool.new(size: 5, timeout: 3) do
  Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'))
end

REDLOCK = Redlock::Client.new([ENV.fetch('REDIS_URL', 'redis://localhost:6379/1')])
