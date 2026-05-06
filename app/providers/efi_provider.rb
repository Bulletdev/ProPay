# frozen_string_literal: true

require 'httpx'
require 'openssl'
require 'base64'

class EfiProvider < BaseProvider
  BASE_URL    = 'https://pix.api.efipay.com.br'
  SANDBOX_URL = 'https://pix-h.api.efipay.com.br'

  def create_charge(amount_cents:, description:, txid:, expires_in:)
    token    = fetch_oauth_token
    base_url = sandbox? ? SANDBOX_URL : BASE_URL

    response = HTTPX.put(
      "#{base_url}/v2/cob/#{txid}",
      headers: {
        'Authorization' => "Bearer #{token}",
        'Content-Type' => 'application/json'
      },
      json: {
        calendario: { expiracao: expires_in },
        valor: { original: format_amount(amount_cents) },
        chave: ENV.fetch('PROPAY_PIX_KEY'),
        solicitacaoPagador: description
      }
    )
    raise "Efi API error: #{response.status}" unless [200, 201].include?(response.status)

    body = Oj.load(response.body.to_s, mode: :compat)
    {
      provider_id: body['txid'],
      qr_code: body['pixCopiaECola'] || build_br_code(body),
      qr_code_url: body['location']
    }
  end

  def cancel_charge(_txid:)
    true
  end

  def verify_webhook(headers:, raw_body:)
    secret = ENV.fetch('PROPAY_EFI_WEBHOOK_SECRET', nil)
    return true unless secret

    received = headers['x-hub-signature'] || headers['X-Hub-Signature']
    return false unless received

    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, raw_body)}"
    secure_compare?(received, expected)
  rescue StandardError
    false
  end

  private

  def fetch_oauth_token
    base_url    = sandbox? ? SANDBOX_URL : BASE_URL
    credentials = Base64.strict_encode64(
      "#{ENV.fetch('PROPAY_EFI_CLIENT_ID')}:#{ENV.fetch('PROPAY_EFI_CLIENT_SECRET')}"
    )

    response = HTTPX.post(
      "#{base_url}/oauth/token",
      headers: {
        'Authorization' => "Basic #{credentials}",
        'Content-Type' => 'application/json'
      },
      json: { grant_type: 'client_credentials' }
    )
    raise "Efi OAuth error: #{response.status}" unless response.status == 200

    Oj.load(response.body.to_s, mode: :compat)['access_token']
  end

  def format_amount(cents)
    format('%.2f', cents.to_f / 100)
  end

  def sandbox?
    ENV.fetch('PROPAY_EFI_SANDBOX', 'false') == 'true'
  end

  def build_br_code(body)
    body['location']
  end
end
