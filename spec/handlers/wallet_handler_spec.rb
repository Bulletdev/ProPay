# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Wallet API', type: :request do
  let(:user_id)  { '7' }
  let(:customer) { create_customer(owner_id: user_id) }

  let(:openpix_success_body) do
    Oj.dump({
              'charge' => {
                'correlationID' => 'deposit-txid-001',
                'brCode' => '00020126580014br.gov.bcb.brcode...',
                'paymentLinkUrl' => 'https://openpix.com.br/pay/deposit-test'
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
    allow(PixWebhookJob).to receive(:perform_async)
  end

  describe 'GET /v1/wallet' do
    context 'without JWT' do
      it 'returns 401' do
        get '/v1/wallet'
        expect(last_response.status).to eq(401)
      end
    end

    context 'when no wallet exists for the user' do
      it 'returns 200 with balance_cents 0' do
        get '/v1/wallet', {}, auth_header(user_id: user_id)
        expect(last_response.status).to eq(200)
        expect(json_body['data']['balance_cents']).to eq(0)
      end
    end

    context 'when a wallet exists' do
      before { create_wallet(user_id: user_id, balance_cents: 2500) }

      it 'returns the correct balance_cents' do
        get '/v1/wallet', {}, auth_header(user_id: user_id)
        expect(last_response.status).to eq(200)
        expect(json_body['data']['balance_cents']).to eq(2500)
      end
    end
  end

  describe 'GET /v1/wallet/transactions' do
    context 'without JWT' do
      it 'returns 401' do
        get '/v1/wallet/transactions'
        expect(last_response.status).to eq(401)
      end
    end

    context 'when no wallet or transactions exist' do
      it 'returns an empty list' do
        get '/v1/wallet/transactions', {}, auth_header(user_id: user_id)
        expect(last_response.status).to eq(200)
        expect(json_body['data']).to eq([])
      end
    end

    context 'when transactions exist' do
      let!(:wallet) { create_wallet(user_id: user_id, balance_cents: 1000) }

      before do
        WalletService.credit!(
          user_id: user_id,
          amount_cents: 600,
          type: 'deposit',
          description: 'First deposit',
          idempotency_key: 'txn-idem-01'
        )
        WalletService.credit!(
          user_id: user_id,
          amount_cents: 400,
          type: 'deposit',
          description: 'Second deposit',
          idempotency_key: 'txn-idem-02'
        )
      end

      it 'returns the transactions' do
        get '/v1/wallet/transactions', {}, auth_header(user_id: user_id)
        expect(last_response.status).to eq(200)
        expect(json_body['data'].length).to be >= 2
      end

      it 'returns transactions ordered by created_at descending' do
        get '/v1/wallet/transactions', {}, auth_header(user_id: user_id)
        timestamps = json_body['data'].map { |t| t['created_at'] }
        expect(timestamps).to eq(timestamps.sort.reverse)
      end

      it 'includes expected fields on each transaction' do
        get '/v1/wallet/transactions', {}, auth_header(user_id: user_id)
        txn = json_body['data'].first
        expect(txn).to include('id', 'amount_cents', 'type', 'description', 'balance_after', 'created_at')
      end
    end
  end

  describe 'POST /v1/wallet/deposit' do
    let(:deposit_body) do
      Oj.dump({ 'amount_cents' => 10_000 }, mode: :compat)
    end

    context 'without JWT' do
      it 'returns 401' do
        post '/v1/wallet/deposit',
             deposit_body,
             { 'CONTENT_TYPE' => 'application/json', 'HTTP_IDEMPOTENCY_KEY' => 'dep-001' }

        expect(last_response.status).to eq(401)
      end
    end

    context 'without Idempotency-Key header' do
      before { customer }

      it 'returns 422' do
        post '/v1/wallet/deposit',
             deposit_body,
             auth_header(user_id: user_id).merge('CONTENT_TYPE' => 'application/json')

        expect(last_response.status).to eq(422)
        expect(json_body['error']).to match(/Idempotency-Key/)
      end
    end

    context 'when customer does not exist' do
      it 'returns 404' do
        post '/v1/wallet/deposit',
             deposit_body,
             auth_header(user_id: '999').merge(
               'CONTENT_TYPE' => 'application/json',
               'HTTP_IDEMPOTENCY_KEY' => 'dep-001'
             )

        expect(last_response.status).to eq(404)
      end
    end

    context 'with a valid request' do
      before { customer }

      it 'returns 201' do
        post '/v1/wallet/deposit',
             deposit_body,
             auth_header(user_id: user_id).merge(
               'CONTENT_TYPE' => 'application/json',
               'HTTP_IDEMPOTENCY_KEY' => 'dep-001'
             )

        expect(last_response.status).to eq(201)
      end

      it 'returns a qr_code' do
        post '/v1/wallet/deposit',
             deposit_body,
             auth_header(user_id: user_id).merge(
               'CONTENT_TYPE' => 'application/json',
               'HTTP_IDEMPOTENCY_KEY' => 'dep-001'
             )

        data = json_body['data']
        expect(data['qr_code']).to be_present
        expect(data['qr_code_url']).to be_present
        expect(data['txid']).to be_present
        expect(data['expires_at']).to be_present
      end
    end
  end

  describe 'POST /v1/wallet/debit' do
    let(:debit_body) do
      Oj.dump({
                'amount_cents' => 300,
                'description' => 'Tournament entry',
                'reference_type' => 'tournament_registration',
                'reference_id' => 42
              }, mode: :compat)
    end

    context 'without JWT' do
      it 'returns 401' do
        post '/v1/wallet/debit',
             debit_body,
             { 'CONTENT_TYPE' => 'application/json', 'HTTP_IDEMPOTENCY_KEY' => 'deb-001' }

        expect(last_response.status).to eq(401)
      end
    end

    context 'with a regular member JWT' do
      it 'returns 403 forbidden' do
        post '/v1/wallet/debit',
             debit_body,
             auth_header(user_id: user_id, role: 'member').merge(
               'CONTENT_TYPE' => 'application/json',
               'HTTP_IDEMPOTENCY_KEY' => 'deb-001'
             )

        expect(last_response.status).to eq(403)
        expect(json_body['error']).to eq('forbidden')
      end
    end

    context 'with sufficient funds (admin caller)' do
      before { create_wallet(user_id: user_id, balance_cents: 1000) }

      it 'returns 200' do
        post '/v1/wallet/debit',
             debit_body,
             auth_header(user_id: user_id, role: 'admin').merge(
               'CONTENT_TYPE' => 'application/json',
               'HTTP_IDEMPOTENCY_KEY' => 'deb-001'
             )

        expect(last_response.status).to eq(200)
      end

      it 'returns the new balance_cents' do
        post '/v1/wallet/debit',
             debit_body,
             auth_header(user_id: user_id, role: 'admin').merge(
               'CONTENT_TYPE' => 'application/json',
               'HTTP_IDEMPOTENCY_KEY' => 'deb-001'
             )

        expect(json_body['data']['balance_cents']).to eq(700)
      end
    end

    context 'with sufficient funds (service caller)' do
      before { create_wallet(user_id: user_id, balance_cents: 1000) }

      it 'returns 200' do
        post '/v1/wallet/debit',
             debit_body,
             auth_header(user_id: user_id, role: 'service').merge(
               'CONTENT_TYPE' => 'application/json',
               'HTTP_IDEMPOTENCY_KEY' => 'deb-001'
             )

        expect(last_response.status).to eq(200)
      end
    end

    context 'with insufficient funds' do
      before { create_wallet(user_id: user_id, balance_cents: 100) }

      it 'returns 422' do
        post '/v1/wallet/debit',
             debit_body,
             auth_header(user_id: user_id, role: 'admin').merge(
               'CONTENT_TYPE' => 'application/json',
               'HTTP_IDEMPOTENCY_KEY' => 'deb-001'
             )

        expect(last_response.status).to eq(422)
        expect(json_body['error']).to eq('insufficient_funds')
      end
    end

    context 'when no wallet exists' do
      it 'returns 422 with insufficient_funds' do
        post '/v1/wallet/debit',
             debit_body,
             auth_header(user_id: user_id, role: 'admin').merge(
               'CONTENT_TYPE' => 'application/json',
               'HTTP_IDEMPOTENCY_KEY' => 'deb-001'
             )

        expect(last_response.status).to eq(422)
        expect(json_body['error']).to eq('insufficient_funds')
      end
    end
  end
end
