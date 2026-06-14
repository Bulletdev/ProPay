# frozen_string_literal: true

class WalletService
  class InsufficientFunds < StandardError
  end

  def self.credit!(user_id:, amount_cents:, type:, description:, idempotency_key:,
                   reference_type: nil, reference_id: nil)
    DB.transaction do
      wallet = Wallet.where(user_id: user_id).for_update.first
      wallet ||= Wallet.create(user_id: user_id, balance_cents: 0)

      existing = WalletTransaction.first(idempotency_key: idempotency_key)
      return existing if existing

      new_balance = wallet.balance_cents + amount_cents
      wallet.update(balance_cents: new_balance)

      WalletTransaction.create(
        wallet_id: wallet.id,
        amount_cents: amount_cents,
        type: type,
        reference_type: reference_type,
        reference_id: reference_id,
        description: description,
        balance_after: new_balance,
        idempotency_key: idempotency_key
      )
    end
  end

  def self.debit!(user_id:, amount_cents:, idempotency_key:, **)
    raise ArgumentError, 'amount_cents must be positive' unless amount_cents.positive?

    DB.transaction do
      existing = WalletTransaction.first(idempotency_key: idempotency_key)
      return existing if existing

      wallet = Wallet.where(user_id: user_id).for_update.first
      unless wallet&.sufficient_funds?(amount_cents)
        raise InsufficientFunds, "insufficient funds for user_id=#{user_id}"
      end

      credit!(user_id: user_id, amount_cents: -amount_cents, idempotency_key: idempotency_key, **)
    end
  end
end
