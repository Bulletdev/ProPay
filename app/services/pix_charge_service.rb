# frozen_string_literal: true

require 'securerandom'

class PixChargeService
  def initialize(customer:)
    @customer = customer
    @provider = build_provider
  end

  def create!(amount_cents:, description:, reference_type:, reference_id:,
              expires_in_seconds:, idempotency_key:)
    existing = Charge.first(idempotency_key: idempotency_key)
    return existing if existing

    txid       = SecureRandom.hex(16)
    expires_at = Time.now.utc + expires_in_seconds

    result = @provider.create_charge(
      amount_cents: amount_cents,
      description: description,
      txid: txid,
      expires_in: expires_in_seconds
    )

    Charge.create(
      customer_id: @customer.id,
      txid: txid,
      provider: provider_name,
      provider_id: result[:provider_id],
      amount_cents: amount_cents,
      status: 'active',
      qr_code: result[:qr_code],
      qr_code_url: result[:qr_code_url],
      reference_type: reference_type,
      reference_id: reference_id,
      expires_at: expires_at,
      idempotency_key: idempotency_key,
      metadata: Sequel.pg_json_wrap({})
    )
  end

  def cancel!(txid:)
    charge = Charge.first(txid: txid, customer_id: @customer.id)
    raise ArgumentError, "charge not found: #{txid}" unless charge
    raise ArgumentError, "charge not cancellable (status=#{charge.status})" unless charge.status == 'active'

    @provider.cancel_charge(txid: txid)
    charge.update(status: 'cancelled')
    charge
  end

  private

  def build_provider
    case provider_name
    when 'efi' then EfiProvider.new
    else OpenpixProvider.new
    end
  end

  def provider_name
    ENV.fetch('PROPAY_PROVIDER', 'openpix')
  end
end
