# frozen_string_literal: true

class PrizeDistribution < Sequel::Model(:propay_prize_distributions)
  PLATFORM_FEE_PERCENT = 0.20
  PRIZE_POOL_PERCENT   = 0.80

  def before_create
    self.created_at ||= Time.now.utc
    super
  end
end
