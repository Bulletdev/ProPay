# frozen_string_literal: true

require 'sidekiq'

class ExpireChargesJob
  include Sidekiq::Job

  sidekiq_options queue: 'low', retry: 3

  def perform
    expired_ids = Charge.where(status: 'active').where { expires_at < Time.now.utc }.select_map(:id)
    return if expired_ids.empty?

    Charge.where(id: expired_ids).update(status: 'expired')
    Sidekiq.logger.info("[ExpireChargesJob] expired=#{expired_ids.size}")

    transition_past_due(expired_ids)
  end

  private

  def transition_past_due(charge_ids)
    subscription_charges = Charge.where(id: charge_ids, reference_type: 'subscription')
                                 .exclude(subscription_id: nil)
                                 .select(:subscription_id)
                                 .map(:subscription_id)

    return if subscription_charges.empty?

    Subscription
      .where(id: subscription_charges, status: 'active')
      .each do |sub|
        sub.update(status: 'past_due')
        SubscriptionRetryJob.perform_in(86_400, sub.id)
        Sidekiq.logger.info("[ExpireChargesJob] subscription=#{sub.id} -> past_due, retry enqueued")
      end
  end
end
