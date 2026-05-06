# frozen_string_literal: true

class WalletTransaction < Sequel::Model(:propay_wallet_transactions)
  TYPES = %w[deposit inscription_debit refund prize_credit saque_debit platform_fee].freeze

  many_to_one :wallet, class: :Wallet, key: :wallet_id

  def before_create
    self.created_at ||= Time.now.utc
    super
  end
end
