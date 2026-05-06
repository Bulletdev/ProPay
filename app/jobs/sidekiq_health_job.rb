# frozen_string_literal: true

require 'sidekiq'
require 'sidekiq/api'
require 'prometheus/client'

class SidekiqHealthJob
  include Sidekiq::Job

  sidekiq_options queue: 'low', retry: 0

  DEAD_QUEUE_THRESHOLD = 5
  GAUGE_NAME           = :propay_sidekiq_dead_queue_size

  def perform
    dead_size = Sidekiq::DeadSet.new.size
    dead_gauge.set(dead_size)

    if dead_size > DEAD_QUEUE_THRESHOLD
      Sidekiq.logger.error("[SidekiqHealthJob] dead_queue_size=#{dead_size} exceeds threshold=#{DEAD_QUEUE_THRESHOLD}")
    else
      Sidekiq.logger.info("[SidekiqHealthJob] dead_queue_size=#{dead_size} ok")
    end
  end

  private

  def dead_gauge
    registry = Prometheus::Client.registry
    existing = registry.get(GAUGE_NAME)
    return existing if existing

    registry.gauge(
      GAUGE_NAME,
      docstring: 'Number of jobs in the Sidekiq dead queue'
    )
  end
end
