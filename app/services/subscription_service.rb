# frozen_string_literal: true

class SubscriptionService
  PLANS = {
    'pro_monthly' => { amount_cents: 4900,  interval: 'month' },
    'pro_annual' => { amount_cents: 47_000, interval: 'year'  },
    'enterprise' => { amount_cents: 0, interval: 'month' }
  }.freeze

  def initialize(customer:)
    @customer = customer
  end

  def create!(plan_name:, trial_days: 14)
    raise ArgumentError, "invalid plan: #{plan_name}" unless PLANS.key?(plan_name)

    existing = active_subscription
    return existing if existing

    plan       = PLANS[plan_name]
    trial_days = trial_days.to_i
    now        = Time.now.utc
    trial_ends = trial_days.positive? ? now + (trial_days * 86_400) : nil
    period_end = trial_ends || advance_period(now, plan[:interval])

    Subscription.create(
      customer_id: @customer.id,
      plan_name: plan_name,
      status: trial_days.positive? ? 'trialing' : 'active',
      amount_cents: plan[:amount_cents],
      interval: plan[:interval],
      trial_ends_at: trial_ends,
      current_period_start: now,
      current_period_end: period_end,
      next_charge_at: period_end,
      payment_failures: 0
    )
  end

  def cancel!(subscription_id:)
    sub = Subscription.first(id: subscription_id, customer_id: @customer.id)
    raise ArgumentError, 'subscription not found' unless sub
    raise ArgumentError, 'already cancelled'      if sub.status == 'cancelled'

    sub.update(
      status: 'cancelled',
      cancelled_at: Time.now.utc,
      ends_at: sub.current_period_end
    )
    sub
  end

  private

  def active_subscription
    Subscription.where(customer_id: @customer.id, status: %w[trialing active]).first
  end

  def advance_period(from, interval)
    case interval
    when 'year' then from + (365 * 86_400)
    else             from + (30  * 86_400)
    end
  end
end
