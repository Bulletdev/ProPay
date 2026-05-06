# frozen_string_literal: true

require 'prometheus/client'

module MetricsService
  REGISTRY = Prometheus::Client.registry

  CHARGES_CREATED = REGISTRY.counter(
    :propay_charges_created_total,
    docstring: 'Total number of PIX charges created',
    labels: %i[provider reference_type]
  )

  CHARGES_PAID = REGISTRY.counter(
    :propay_charges_paid_total,
    docstring: 'Total number of PIX charges confirmed as paid',
    labels: %i[provider]
  )

  CHARGES_EXPIRED = REGISTRY.counter(
    :propay_charges_expired_total,
    docstring: 'Total number of PIX charges expired',
    labels: %i[provider]
  )

  WALLET_CREDITS = REGISTRY.counter(
    :propay_wallet_credits_total,
    docstring: 'Total wallet credit operations',
    labels: %i[type]
  )

  WALLET_DEBITS = REGISTRY.counter(
    :propay_wallet_debits_total,
    docstring: 'Total wallet debit operations',
    labels: %i[type]
  )

  WEBHOOKS_RECEIVED = REGISTRY.counter(
    :propay_webhooks_received_total,
    docstring: 'Total webhooks received',
    labels: %i[provider event_type]
  )

  WEBHOOK_PROCESSING_DURATION = REGISTRY.histogram(
    :propay_webhook_processing_seconds,
    docstring: 'Time to process a webhook event',
    labels: %i[provider],
    buckets: [0.01, 0.05, 0.1, 0.5, 1.0, 3.0]
  )

  ACTIVE_SUBSCRIPTIONS = REGISTRY.gauge(
    :propay_active_subscriptions,
    docstring: 'Number of active subscriptions',
    labels: %i[plan]
  )

  def self.charge_created(provider:, reference_type:)
    CHARGES_CREATED.increment(labels: { provider: provider, reference_type: reference_type.to_s })
  end

  def self.charge_paid(provider:)
    CHARGES_PAID.increment(labels: { provider: provider })
  end

  def self.charge_expired(provider:)
    CHARGES_EXPIRED.increment(labels: { provider: provider })
  end

  def self.wallet_credited(type:)
    WALLET_CREDITS.increment(labels: { type: type })
  end

  def self.wallet_debited(type:)
    WALLET_DEBITS.increment(labels: { type: type })
  end

  def self.webhook_received(provider:, event_type:)
    WEBHOOKS_RECEIVED.increment(labels: { provider: provider, event_type: event_type })
  end

  def self.measure_webhook(provider:, &block)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    block.call
  ensure
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    WEBHOOK_PROCESSING_DURATION.observe(elapsed, labels: { provider: provider })
  end

  def self.refresh_subscription_gauges
    SUPPORTED_PLANS.each do |plan|
      count = Subscription.where(status: 'active', plan_name: plan).count
      ACTIVE_SUBSCRIPTIONS.set(count, labels: { plan: plan })
    end
  end
end
