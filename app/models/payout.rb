# frozen_string_literal: true

class Payout < Sequel::Model(:propay_payouts)
  STATUSES = %w[pending processing completed failed].freeze

  many_to_one :wallet, class: :Wallet, key: :wallet_id

  def before_create
    self.created_at ||= Time.now.utc
    super
  end
end
