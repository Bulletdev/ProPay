# frozen_string_literal: true

class RefundService
  CDC_WINDOW_DAYS = 7

  class RefundError < StandardError
  end

  class OutsideCdcWindow < RefundError
  end

  class ChargeNotRefundable < RefundError
  end

  def initialize(charge:)
    @charge = charge
  end

  def refund_to_wallet!(idempotency_key:)
    existing = WalletTransaction.first(idempotency_key: idempotency_key)
    return existing if existing

    validate!

    DB.transaction do
      @charge.update(status: 'refunded')

      WalletService.credit!(
        user_id: @charge.customer.owner_id,
        amount_cents: @charge.amount_cents,
        type: 'refund',
        description: "Refund for charge #{@charge.txid}",
        idempotency_key: idempotency_key,
        reference_type: 'charge',
        reference_id: @charge.id.to_s
      )
    end
  end

  private

  def validate!
    raise ChargeNotRefundable, "charge status must be 'paid', got '#{@charge.status}'" unless @charge.status == 'paid'
    raise ChargeNotRefundable, 'charge has no paid_at timestamp' unless @charge.paid_at

    days_since_payment = (Time.now.utc - @charge.paid_at) / 86_400
    return unless days_since_payment > CDC_WINDOW_DAYS

    raise OutsideCdcWindow,
          "refund window expired (#{days_since_payment.floor} days since payment)"
  end
end
