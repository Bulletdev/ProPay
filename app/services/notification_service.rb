# frozen_string_literal: true

module NotificationService
  module_function

  def payout_2fa_required(user_id:, payout_id:, amount_cents:)
    Sidekiq.logger.info(
      event: 'notification.payout_2fa_required',
      user_id: user_id,
      payout_id: payout_id,
      amount_cents: amount_cents
    )
  end

  def subscription_charge_pending(user_id:, amount_cents:, plan_name:, qr_code_url:)
    Sidekiq.logger.info(
      event: 'notification.subscription_charge_pending',
      user_id: user_id,
      amount_cents: amount_cents,
      plan_name: plan_name,
      qr_code_url: qr_code_url
    )
  end

  def prize_received(user_id:, amount_cents:, tournament_id:)
    Sidekiq.logger.info(
      event: 'notification.prize_received',
      user_id: user_id,
      amount_cents: amount_cents,
      tournament_id: tournament_id
    )
  end
end
