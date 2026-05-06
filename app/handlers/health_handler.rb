# frozen_string_literal: true

module HealthHandler
  def self.status
    { status: 'ok', version: PROPAY_VERSION }
  end

  def self.ready
    DB.test_connection
    REDIS_POOL.with(&:ping)
    { ok: true, status: 'ok' }
  rescue StandardError => e
    { ok: false, status: 'unavailable', error: e.message }
  end
end
