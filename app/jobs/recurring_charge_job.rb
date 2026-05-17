# frozen_string_literal: true

require 'sidekiq'

class RecurringChargeJob
  include Sidekiq::Job

  sidekiq_options queue: 'default', retry: 3

  def perform
    Subscription.where(status: 'active').where { next_charge_at <= Time.now.utc }.each do |sub|
      create_renewal_charge(sub)
    rescue StandardError => e
      Sidekiq.logger.error("[RecurringChargeJob] sub_id=#{sub.id} error=#{e.message}")
    end
  end

  private

  def create_renewal_charge(sub)
    service = PixChargeService.new(customer: sub.customer)
    service.create!(
      amount_cents: sub.amount_cents,
      description: "ProStaff #{sub.plan_name} renewal",
      reference_type: 'subscription',
      reference_id: sub.id.to_s,
      subscription_id: sub.id,
      expires_in_seconds: 86_400 * 3,
      idempotency_key: "recurring_#{sub.id}_#{sub.next_charge_at.to_i}"
    )
  end
end
