# frozen_string_literal: true

class Wallet < Sequel::Model(:propay_wallets)
  one_to_many :transactions, class: :WalletTransaction, key: :wallet_id

  def sufficient_funds?(amount_cents)
    balance_cents >= amount_cents
  end

  def before_create
    self.created_at ||= Time.now.utc
    self.updated_at ||= Time.now.utc
    super
  end

  def before_update
    self.updated_at = Time.now.utc
    super
  end
end
