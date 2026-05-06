# frozen_string_literal: true

require 'sidekiq'

class PixWebhookJob
  include Sidekiq::Job

  sidekiq_options queue: 'critical', retry: 5

  def perform(webhook_event_id)
    event = WebhookEvent[webhook_event_id]
    return unless event&.status == 'pending'

    end_to_end_id = extract_e2e_id(event.payload)
    charge        = resolve_charge(event)
    return unless charge

    DB.transaction do
      charge.update(status: 'paid', end_to_end_id: end_to_end_id, paid_at: Time.now.utc)
      process_reference(charge, end_to_end_id)
      event.update(status: 'processed', processed_at: Time.now.utc, attempts: event.attempts + 1)
    end
  rescue StandardError => e
    event&.update(status: 'failed', error_message: e.message, attempts: (event&.attempts || 0) + 1)
    raise
  end

  private

  def extract_e2e_id(payload)
    payload.dig('pix', 0, 'endToEndId') || payload['endToEndId']
  end

  def resolve_charge(event)
    payload = event.payload
    txid    = payload.dig('charge', 'correlationID') || payload['correlationID']
    charge  = Charge.first(txid: txid)
    unless charge
      event.update(status: 'failed', error_message: "charge not found txid=#{txid}",
                   attempts: event.attempts + 1)
    end
    charge
  end

  def process_reference(charge, end_to_end_id)
    case charge.reference_type
    when 'wallet_deposit'  then credit_wallet(charge, end_to_end_id)
    when 'subscription'    then activate_subscription(charge)
    end
  end

  def credit_wallet(charge, end_to_end_id)
    WalletService.credit!(
      user_id: charge.customer.owner_id,
      amount_cents: charge.amount_cents,
      type: 'deposit',
      description: 'PIX deposit confirmed',
      idempotency_key: "deposit_#{end_to_end_id}",
      reference_type: 'charge',
      reference_id: charge.id
    )
  end

  def activate_subscription(charge)
    return unless charge.subscription_id

    sub = Subscription[charge.subscription_id]
    return unless sub

    period_end = Time.now.utc + (sub.interval == 'year' ? 365 * 86_400 : 30 * 86_400)
    sub.update(
      status: 'active',
      payment_failures: 0,
      current_period_start: Time.now.utc,
      current_period_end: period_end,
      next_charge_at: period_end
    )
    TierSyncJob.perform_async(sub.customer.owner_id, sub.plan_name)
  end
end
