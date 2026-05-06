# frozen_string_literal: true

require 'sidekiq'
require 'httpx'

class TierSyncJob
  include Sidekiq::Job

  sidekiq_options queue: 'critical', retry: 5

  TIER_MAP = {
    'pro_monthly' => 'tier_2_semi_pro',
    'pro_annual' => 'tier_2_semi_pro',
    'enterprise' => 'tier_3_enterprise'
  }.freeze

  def perform(owner_id, plan_name)
    tier = TIER_MAP.fetch(plan_name.to_s, 'tier_1_free')
    url  = "#{ENV.fetch('PROSTAFF_API_URL')}/internal/organizations/#{owner_id}/tier"

    HTTPX.patch(
      url,
      headers: {
        'Authorization' => "Bearer #{ENV.fetch('INTERNAL_JWT_SECRET')}",
        'Content-Type' => 'application/json'
      },
      json: { tier: tier, subscription_plan: plan_name }
    )
  end
end
