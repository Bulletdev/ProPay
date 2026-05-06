# frozen_string_literal: true

module Middleware
  module Idempotency
    TTL = 86_400

    def self.key_for(user_id, idempotency_key)
      "propay:idem:#{user_id}:#{idempotency_key}"
    end

    def self.fetch(user_id, idempotency_key)
      return nil unless idempotency_key

      REDIS_POOL.with do |redis|
        cached = redis.get(key_for(user_id, idempotency_key))
        Oj.load(cached, mode: :compat) if cached
      end
    end

    def self.store(user_id, idempotency_key, body)
      return unless idempotency_key

      REDIS_POOL.with do |redis|
        redis.setex(key_for(user_id, idempotency_key), TTL, Oj.dump(body, mode: :compat))
      end
    end
  end
end
