# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Charges API', type: :request do
  let(:user_id)  { '1' }
  let(:customer) { create_customer(owner_id: user_id) }
  let(:txid)     { 'aabbccddeeff00112233445566778899' }

  let(:openpix_success_body) do
    Oj.dump({
              'charge' => {
                'correlationID' => txid,
                'brCode' => '00020126580014br.gov.bcb.brcode...',
                'paymentLinkUrl' => 'https://openpix.com.br/pay/test'
              }
            }, mode: :compat)
  end

  before do
    stub_request(:post, 'https://api.openpix.com.br/api/v1/charge')
      .to_return(
        status: 200,
        body: openpix_success_body,
        headers: { 'Content-Type' => 'application/json' }
      )
    stub_request(:delete, %r{https://api\.openpix\.com\.br/api/v1/charge/.*})
      .to_return(status: 200, body: '{}')
  end

  describe 'POST /v1/charges' do
    let(:valid_body) do
      Oj.dump({
                'amount_cents' => 5000,
                'description' => 'Test charge',
                'reference_type' => 'wallet_deposit',
                'reference_id' => 1,
                'expires_in_seconds' => 3600
              }, mode: :compat)
    end

    context 'without JWT' do
      it 'returns 401' do
        post '/v1/charges',
             valid_body,
             { 'CONTENT_TYPE' => 'application/json', 'HTTP_IDEMPOTENCY_KEY' => 'idem-001' }

        expect(last_response.status).to eq(401)
      end
    end

    context 'without Idempotency-Key header' do
      before { customer }

      it 'returns 422' do
        post '/v1/charges',
             valid_body,
             auth_header(user_id: user_id).merge('CONTENT_TYPE' => 'application/json')

        expect(last_response.status).to eq(422)
        expect(json_body['error']).to match(/Idempotency-Key/)
      end
    end

    context 'when customer does not exist' do
      it 'returns 404' do
        post '/v1/charges',
             valid_body,
             auth_header(user_id: '999').merge(
               'CONTENT_TYPE' => 'application/json',
               'HTTP_IDEMPOTENCY_KEY' => 'idem-001'
             )

        expect(last_response.status).to eq(404)
        expect(json_body['error']).to eq('customer not found')
      end
    end

    context 'with valid request' do
      before { customer }

      it 'returns 201' do
        post '/v1/charges',
             valid_body,
             auth_header(user_id: user_id).merge(
               'CONTENT_TYPE' => 'application/json',
               'HTTP_IDEMPOTENCY_KEY' => 'idem-001'
             )

        expect(last_response.status).to eq(201)
      end

      it 'returns the charge data' do
        post '/v1/charges',
             valid_body,
             auth_header(user_id: user_id).merge(
               'CONTENT_TYPE' => 'application/json',
               'HTTP_IDEMPOTENCY_KEY' => 'idem-001'
             )

        data = json_body['data']
        expect(data['status']).to eq('active')
        expect(data['amount_cents']).to eq(5000)
        expect(data['qr_code']).to be_present
        expect(data['qr_code_url']).to be_present
        expect(data['txid']).to be_present
      end
    end
  end

  describe 'GET /v1/charges/:txid' do
    let!(:charge) do
      customer
      Charge.create(
        customer_id: customer.id,
        txid: txid,
        provider: 'openpix',
        provider_id: txid,
        amount_cents: 3000,
        status: 'active',
        qr_code: 'some-brcode',
        qr_code_url: 'https://openpix.com.br/pay/test',
        reference_type: 'wallet_deposit',
        reference_id: user_id,
        expires_at: Time.now.utc + 3600,
        idempotency_key: 'get-test-idem',
        metadata: Sequel.pg_json_wrap({})
      )
    end

    context 'without JWT' do
      it 'returns 401' do
        get "/v1/charges/#{txid}"
        expect(last_response.status).to eq(401)
      end
    end

    context 'with valid JWT and existing charge' do
      it 'returns 200' do
        get "/v1/charges/#{txid}", {}, auth_header(user_id: user_id)
        expect(last_response.status).to eq(200)
      end

      it 'returns the charge payload' do
        get "/v1/charges/#{txid}", {}, auth_header(user_id: user_id)
        data = json_body['data']
        expect(data['txid']).to eq(txid)
        expect(data['status']).to eq('active')
        expect(data['amount_cents']).to eq(3000)
      end
    end

    context 'with a txid that does not exist' do
      it 'returns 404' do
        get '/v1/charges/nonexistent-txid', {}, auth_header(user_id: user_id)
        expect(last_response.status).to eq(404)
      end
    end

    context 'when charge belongs to a different customer' do
      let(:other_user_id) { '888' }
      let!(:other_customer) { create_customer(owner_id: other_user_id, email: 'other@propay.gg') }

      it 'returns 404' do
        get "/v1/charges/#{txid}", {}, auth_header(user_id: other_user_id)
        expect(last_response.status).to eq(404)
      end
    end
  end

  describe 'DELETE /v1/charges/:txid' do
    let!(:charge) do
      customer
      Charge.create(
        customer_id: customer.id,
        txid: txid,
        provider: 'openpix',
        provider_id: txid,
        amount_cents: 3000,
        status: 'active',
        qr_code: 'some-brcode',
        qr_code_url: 'https://openpix.com.br/pay/test',
        reference_type: 'wallet_deposit',
        reference_id: user_id,
        expires_at: Time.now.utc + 3600,
        idempotency_key: 'delete-test-idem',
        metadata: Sequel.pg_json_wrap({})
      )
    end

    context 'without JWT' do
      it 'returns 401' do
        delete "/v1/charges/#{txid}"
        expect(last_response.status).to eq(401)
      end
    end

    context 'with a valid active charge' do
      it 'returns 200' do
        delete "/v1/charges/#{txid}", {}, auth_header(user_id: user_id)
        expect(last_response.status).to eq(200)
      end

      it 'returns the cancelled charge' do
        delete "/v1/charges/#{txid}", {}, auth_header(user_id: user_id)
        data = json_body['data']
        expect(data['txid']).to eq(txid)
        expect(data['status']).to eq('cancelled')
      end
    end

    context 'when the charge is already cancelled' do
      before { charge.update(status: 'cancelled') }

      it 'returns 422' do
        delete "/v1/charges/#{txid}", {}, auth_header(user_id: user_id)
        expect(last_response.status).to eq(422)
      end
    end

    context 'when the txid does not exist for the customer' do
      it 'returns 422' do
        delete '/v1/charges/no-such-txid', {}, auth_header(user_id: user_id)
        expect(last_response.status).to eq(422)
      end
    end
  end
end
