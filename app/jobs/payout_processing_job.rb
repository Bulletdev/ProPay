# frozen_string_literal: true

require 'sidekiq'

class PayoutProcessingJob
  include Sidekiq::Job

  sidekiq_options queue: 'default', retry: 3

  MIN_HOURS_AFTER_DEPOSIT = 24
  LARGE_PAYOUT_THRESHOLD  = 50_000

  def perform(payout_id)
    payout = Payout[payout_id]
    return unless payout&.status == 'pending'

    wallet = payout.wallet
    return fail_payout!(payout, 'wallet not found') unless wallet

    error = validation_error(payout, wallet)
    return fail_payout!(payout, error) if error

    notify_if_large(payout, wallet)
    payout.update(status: 'processing')
    process_pix_out(payout, wallet)
  rescue StandardError => e
    fail_payout!(payout, e.message) if payout
    raise
  end

  private

  def validation_error(payout, wallet)
    return 'insufficient funds' unless wallet.sufficient_funds?(payout.amount_cents)
    return 'anti-fraud: withdrawal too soon after last deposit' unless anti_fraud_cleared?(wallet)
    return "invalid pix key for type #{payout.pix_key_type}" unless PixKeyValidator.valid?(payout.pix_key_type,
                                                                                           payout.pix_key)

    nil
  end

  def anti_fraud_cleared?(wallet)
    last_deposit = WalletTransaction
                   .where(wallet_id: wallet.id, type: 'deposit')
                   .order(Sequel.desc(:created_at))
                   .first

    return true unless last_deposit

    (Time.now.utc - last_deposit.created_at) / 3600 >= MIN_HOURS_AFTER_DEPOSIT
  end

  def notify_if_large(payout, wallet)
    return unless payout.amount_cents > LARGE_PAYOUT_THRESHOLD

    NotificationService.payout_2fa_required(
      user_id: wallet.user_id,
      payout_id: payout.id,
      amount_cents: payout.amount_cents
    )
  end

  def process_pix_out(payout, wallet)
    DB.transaction do
      WalletService.debit!(
        user_id: wallet.user_id,
        amount_cents: payout.amount_cents,
        type: 'saque_debit',
        description: "Payout #{payout.id} via PIX #{payout.pix_key_type}",
        idempotency_key: "payout_debit_#{payout.id}"
      )
      payout.update(
        status: 'completed',
        completed_at: Time.now.utc,
        provider_transfer_id: "sandbox_#{payout.id}"
      )
    end
  rescue WalletService::InsufficientFunds => e
    fail_payout!(payout, e.message)
  end

  def fail_payout!(payout, reason)
    payout.update(status: 'failed', failed_at: Time.now.utc, failure_reason: reason)
  end
end
