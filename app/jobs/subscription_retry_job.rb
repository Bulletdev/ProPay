# frozen_string_literal: true

require 'sidekiq'

class SubscriptionRetryJob
  include Sidekiq::Job

  sidekiq_options queue: 'default', retry: 3

  MAX_FAILURES = 3

  def perform(subscription_id)
    sub = Subscription[subscription_id]
    return unless sub&.status == 'past_due'

    if sub.payment_failures >= MAX_FAILURES
      sub.update(status: 'cancelled', cancelled_at: Time.now.utc)
      TierSyncJob.perform_async(sub.customer.owner_id, nil)
      return
    end

    retry_num = sub.payment_failures + 1
    PixChargeService.new(customer: sub.customer).create!(
      amount_cents: sub.amount_cents,
      description: "ProStaff #{sub.plan_name} retry #{retry_num}",
      reference_type: 'subscription',
      reference_id: sub.id,
      expires_in_seconds: 86_400,
      idempotency_key: "retry_#{sub.id}_#{retry_num}"
    )
    sub.update(payment_failures: retry_num)
  end
end
