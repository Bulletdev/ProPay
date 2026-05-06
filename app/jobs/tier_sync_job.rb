# frozen_string_literal: true

require 'sidekiq'
require 'httpx'

class TierSyncJob
  include Sidekiq::Job

  sidekiq_options queue: 'critical', retry: 5

  TIER_MAP = {
    'pro_monthly' => 'tier_2_semi_pro',
    'pro_annual'  => 'tier_2_semi_pro',
    'enterprise'  => 'tier_1_professional'
  }.freeze

  PLAN_MAP = {
    'pro_monthly' => 'semi_pro',
    'pro_annual'  => 'professional',
    'enterprise'  => 'enterprise'
  }.freeze

  DEFAULT_TIER = 'tier_3_amateur'
  DEFAULT_PLAN = 'free'

  def perform(user_id, plan_name)
    tier   = plan_name ? TIER_MAP.fetch(plan_name.to_s, DEFAULT_TIER) : DEFAULT_TIER
    plan   = plan_name ? PLAN_MAP.fetch(plan_name.to_s, DEFAULT_PLAN) : DEFAULT_PLAN
    status = plan_name ? 'active' : 'cancelled'
    url    = "#{ENV.fetch('PROSTAFF_API_URL')}/internal/organizations/by_user/#{user_id}/tier"

    HTTPX.patch(
      url,
      headers: {
        'Authorization' => "Bearer #{ENV.fetch('INTERNAL_JWT_SECRET')}",
        'Content-Type'  => 'application/json'
      },
      json: { tier: tier, subscription_plan: plan, subscription_status: status }
    )
  end
end
