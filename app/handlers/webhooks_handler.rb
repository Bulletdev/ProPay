# frozen_string_literal: true

class WebhooksHandler
  def initialize(request)
    @r = request
  end

  def call
    @r.on 'openpix' do
      @r.post do
        raw_body = @r.body.read
        provider = OpenpixProvider.new

        unless provider.verify_webhook(headers: @r.env, raw_body: raw_body)
          @r.halt(401, Oj.dump({ error: 'invalid_signature' }, mode: :compat))
        end

        payload    = Oj.load(raw_body, mode: :compat)
        event_type = payload['event'] || 'OPENPIX:CHARGE_COMPLETED'
        idem_key   = extract_idem_key(payload)

        unless idem_key
          Sidekiq.logger.warn("[WebhooksHandler] missing idempotency key payload=#{raw_body.to_s[0, 300]}")
          @r.halt(422, Oj.dump({ error: 'missing_idempotency_key' }, mode: :compat))
        end

        return Oj.dump({ status: 'already_processed' }, mode: :compat) if WebhookEvent.first(idempotency_key: idem_key)

        event = WebhookEvent.create(
          provider: 'openpix',
          event_type: event_type,
          idempotency_key: idem_key,
          status: 'pending',
          payload: Sequel.pg_json_wrap(payload),
          attempts: 0
        )

        PixWebhookJob.perform_async(event.id) if payment_event?(event_type)

        Oj.dump({ status: 'received' }, mode: :compat)
      end
    end
  end

  private

  def extract_idem_key(payload)
    payload.dig('pix', 0, 'endToEndId') ||
      payload['endToEndId'] ||
      payload.dig('charge', 'correlationID')
  end

  def payment_event?(event_type)
    event_type.include?('COMPLETED') ||
      event_type.include?('PAID') ||
      event_type.include?('CHARGE_COMPLETED')
  end
end
