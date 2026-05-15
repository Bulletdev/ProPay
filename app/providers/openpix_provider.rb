# frozen_string_literal: true

require 'httpx'
require 'openssl'

class OpenpixProvider < BaseProvider
  BASE_URL = 'https://api.openpix.com.br/api/v1'

  def create_charge(amount_cents:, description:, txid:, expires_in:)
    response = HTTPX.post(
      "#{BASE_URL}/charge",
      headers: auth_headers,
      json: {
        correlationID: txid,
        value: amount_cents,
        comment: description,
        expiresIn: expires_in
      }
    )
    raise "OpenPix API error: #{response.status}" unless [200, 201].include?(response.status)

    body   = Oj.load(response.body.to_s, mode: :compat)
    charge = body['charge']
    {
      provider_id: charge['correlationID'],
      qr_code: charge['brCode'],
      qr_code_url: charge['paymentLinkUrl']
    }
  end

  def cancel_charge(txid:)
    response = HTTPX.delete("#{BASE_URL}/charge/#{txid}", headers: auth_headers)
    [200, 204].include?(response.status)
  end

  def verify_webhook(headers:, raw_body:)
    received = headers['x-webhook-signature'] || headers['X-Webhook-Signature']
    return false unless received

    secrets = [
      ENV.fetch('PROPAY_OPENPIX_SECRET', nil),
      ENV.fetch('PROPAY_OPENPIX_SECRET_PREV', nil)
    ].compact.reject(&:empty?)

    secrets.any? do |secret|
      expected = OpenSSL::HMAC.hexdigest('SHA256', secret, raw_body)
      secure_compare?(received, expected)
    end
  rescue StandardError
    false
  end

  private

  def auth_headers
    {
      'Authorization' => ENV.fetch('PROPAY_OPENPIX_APP_ID'),
      'Content-Type' => 'application/json'
    }
  end
end
