# frozen_string_literal: true

require 'spec_helper'
require 'openssl'

RSpec.describe 'Webhooks API', type: :request do
  let(:openpix_secret) { ENV.fetch('PROPAY_OPENPIX_SECRET') }

  def openpix_signature(raw_body)
    OpenSSL::HMAC.hexdigest('SHA256', openpix_secret, raw_body)
  end

  def post_openpix_webhook(body_hash, signature: nil)
    raw_body = Oj.dump(body_hash, mode: :compat)
    sig      = signature || openpix_signature(raw_body)

    post '/v1/webhooks/openpix',
         raw_body,
         {
           'CONTENT_TYPE' => 'application/json',
           'x-webhook-signature' => sig
         }
  end

  let(:valid_payload) do
    {
      'event' => 'OPENPIX:CHARGE_COMPLETED',
      'charge' => {
        'correlationID' => 'txid-webhook-001',
        'value' => 2000
      },
      'pix' => [{ 'endToEndId' => 'E00000000000000000000000000001' }]
    }
  end

  before do
    allow(PixWebhookJob).to receive(:perform_async)
  end

  describe 'POST /v1/webhooks/openpix' do
    context 'with an invalid HMAC signature' do
      it 'returns 401' do
        post_openpix_webhook(valid_payload, signature: 'deadbeefdeadbeef')
        expect(last_response.status).to eq(401)
        expect(json_body['error']).to eq('invalid_signature')
      end
    end

    context 'with a valid HMAC signature' do
      it 'returns 200' do
        post_openpix_webhook(valid_payload)
        expect(last_response.status).to eq(200)
      end

      it 'returns received status' do
        post_openpix_webhook(valid_payload)
        expect(json_body['status']).to eq('received')
      end
    end

    context 'webhook event persistence' do
      it 'creates a WebhookEvent record in the database' do
        expect do
          post_openpix_webhook(valid_payload)
        end.to change { WebhookEvent.count }.by(1)
      end

      it 'stores the event with status pending' do
        post_openpix_webhook(valid_payload)
        event = WebhookEvent.order(:created_at).last
        expect(event.status).to eq('pending')
      end

      it 'stores the correct provider' do
        post_openpix_webhook(valid_payload)
        event = WebhookEvent.order(:created_at).last
        expect(event.provider).to eq('openpix')
      end

      it 'stores the correct event_type' do
        post_openpix_webhook(valid_payload)
        event = WebhookEvent.order(:created_at).last
        expect(event.event_type).to eq('OPENPIX:CHARGE_COMPLETED')
      end
    end

    context 'idempotency' do
      it 'returns already_processed on the second request with the same endToEndId' do
        post_openpix_webhook(valid_payload)
        expect(last_response.status).to eq(200)

        post_openpix_webhook(valid_payload)
        expect(last_response.status).to eq(200)
        expect(json_body['status']).to eq('already_processed')
      end

      it 'does not create a second WebhookEvent for the same endToEndId' do
        post_openpix_webhook(valid_payload)

        expect do
          post_openpix_webhook(valid_payload)
        end.not_to(change { WebhookEvent.count })
      end
    end

    context 'job enqueueing' do
      it 'enqueues PixWebhookJob for a COMPLETED event' do
        post_openpix_webhook(valid_payload)

        expect(PixWebhookJob).to have_received(:perform_async).once
      end

      it 'passes the WebhookEvent id to PixWebhookJob' do
        post_openpix_webhook(valid_payload)

        event = WebhookEvent.order(:created_at).last
        expect(PixWebhookJob).to have_received(:perform_async).with(event.id)
      end

      it 'does not enqueue PixWebhookJob for a non-payment event' do
        non_payment_payload = valid_payload.merge('event' => 'OPENPIX:CHARGE_CREATED')

        post_openpix_webhook(non_payment_payload)

        expect(PixWebhookJob).not_to have_received(:perform_async)
      end
    end

    context 'with missing Authorization header but valid HMAC' do
      it 'still returns 200 (webhooks bypass auth middleware)' do
        post_openpix_webhook(valid_payload)
        expect(last_response.status).to eq(200)
      end
    end

    context 'when payload has no identifiable idempotency key' do
      let(:keyless_payload) do
        {
          'event' => 'OPENPIX:CHARGE_COMPLETED',
          'charge' => { 'value' => 1000 }
          # no pix[].endToEndId, no endToEndId, no charge.correlationID
        }
      end

      it 'returns 422' do
        post_openpix_webhook(keyless_payload)
        expect(last_response.status).to eq(422)
      end

      it 'returns missing_idempotency_key error' do
        post_openpix_webhook(keyless_payload)
        expect(json_body['error']).to eq('missing_idempotency_key')
      end

      it 'does not create a WebhookEvent' do
        expect { post_openpix_webhook(keyless_payload) }
          .not_to(change { WebhookEvent.count })
      end

      it 'does not enqueue PixWebhookJob' do
        post_openpix_webhook(keyless_payload)
        expect(PixWebhookJob).not_to have_received(:perform_async)
      end
    end
  end
end
