# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Admin API', type: :request do
  let(:admin_id)  { 100 }
  let(:member_id) { 200 }

  describe 'authorization' do
    it 'returns 403 when the user does not have the admin role' do
      get '/v1/admin/dashboard', {}, auth_header(user_id: member_id, role: 'member')
      expect(last_response.status).to eq(403)
      expect(json_body['error']).to eq('admin_required')
    end
  end

  describe 'GET /v1/admin/dashboard' do
    context 'when authenticated as admin' do
      it 'returns 200' do
        get '/v1/admin/dashboard', {}, auth_header(user_id: admin_id, role: 'admin')
        expect(last_response.status).to eq(200)
      end

      it 'returns the charges summary key' do
        get '/v1/admin/dashboard', {}, auth_header(user_id: admin_id, role: 'admin')
        expect(json_body['data']).to have_key('charges')
      end

      it 'returns the subscriptions summary key' do
        get '/v1/admin/dashboard', {}, auth_header(user_id: admin_id, role: 'admin')
        expect(json_body['data']).to have_key('subscriptions')
      end

      it 'returns the wallets summary key' do
        get '/v1/admin/dashboard', {}, auth_header(user_id: admin_id, role: 'admin')
        expect(json_body['data']).to have_key('wallets')
      end

      it 'returns the payouts summary key' do
        get '/v1/admin/dashboard', {}, auth_header(user_id: admin_id, role: 'admin')
        expect(json_body['data']).to have_key('payouts')
      end
    end
  end

  describe 'GET /v1/admin/subscriptions' do
    let(:customer) { create_customer(owner_id: admin_id, email: 'admin@propay.gg') }

    let!(:active_sub) do
      Subscription.create(
        customer_id: customer.id,
        plan_name: 'pro_monthly',
        status: 'active',
        amount_cents: 4900,
        interval: 'month',
        current_period_start: Time.now.utc - 86_400,
        current_period_end: Time.now.utc + (29 * 86_400),
        next_charge_at: Time.now.utc + (29 * 86_400),
        payment_failures: 0
      )
    end

    let!(:cancelled_sub) do
      Subscription.create(
        customer_id: customer.id,
        plan_name: 'pro_annual',
        status: 'cancelled',
        amount_cents: 49_900,
        interval: 'year',
        current_period_start: Time.now.utc - (365 * 86_400),
        current_period_end: Time.now.utc - 86_400,
        next_charge_at: Time.now.utc - 86_400,
        payment_failures: 0
      )
    end

    context 'without status filter' do
      it 'returns 200' do
        get '/v1/admin/subscriptions', {}, auth_header(user_id: admin_id, role: 'admin')
        expect(last_response.status).to eq(200)
      end

      it 'returns a list of subscriptions' do
        get '/v1/admin/subscriptions', {}, auth_header(user_id: admin_id, role: 'admin')
        expect(json_body['data'].length).to eq(2)
      end

      it 'includes pagination metadata' do
        get '/v1/admin/subscriptions', {}, auth_header(user_id: admin_id, role: 'admin')
        meta = json_body['meta']
        expect(meta).to include('total', 'page', 'per_page')
        expect(meta['total']).to eq(2)
        expect(meta['page']).to eq(1)
      end
    end

    context 'with status=active filter' do
      it 'returns only active subscriptions' do
        get '/v1/admin/subscriptions?status=active', {}, auth_header(user_id: admin_id, role: 'admin')
        data = json_body['data']
        expect(data.length).to eq(1)
        expect(data.first['status']).to eq('active')
      end

      it 'reflects the filtered total in meta' do
        get '/v1/admin/subscriptions?status=active', {}, auth_header(user_id: admin_id, role: 'admin')
        expect(json_body['meta']['total']).to eq(1)
      end
    end
  end

  describe 'GET /v1/admin/charges' do
    let(:customer) { create_customer(owner_id: admin_id, email: 'admin-charges@propay.gg') }

    let!(:paid_charge) do
      Charge.create(
        customer_id: customer.id,
        txid: 'admin-txid-paid-001',
        provider: 'openpix',
        provider_id: 'admin-txid-paid-001',
        amount_cents: 5000,
        status: 'paid',
        qr_code: 'brcode-paid',
        qr_code_url: 'https://openpix.com.br/pay/paid',
        reference_type: 'wallet_deposit',
        reference_id: admin_id,
        expires_at: Time.now.utc + 3600,
        paid_at: Time.now.utc,
        idempotency_key: 'admin-paid-idem-001',
        metadata: Sequel.pg_json_wrap({})
      )
    end

    let!(:pending_charge) do
      Charge.create(
        customer_id: customer.id,
        txid: 'admin-txid-pending-001',
        provider: 'openpix',
        provider_id: 'admin-txid-pending-001',
        amount_cents: 2500,
        status: 'active',
        qr_code: 'brcode-pending',
        qr_code_url: 'https://openpix.com.br/pay/pending',
        reference_type: 'wallet_deposit',
        reference_id: admin_id,
        expires_at: Time.now.utc + 3600,
        idempotency_key: 'admin-pending-idem-001',
        metadata: Sequel.pg_json_wrap({})
      )
    end

    context 'without status filter' do
      it 'returns 200' do
        get '/v1/admin/charges', {}, auth_header(user_id: admin_id, role: 'admin')
        expect(last_response.status).to eq(200)
      end

      it 'returns a list of charges' do
        get '/v1/admin/charges', {}, auth_header(user_id: admin_id, role: 'admin')
        expect(json_body['data'].length).to eq(2)
      end

      it 'includes pagination metadata' do
        get '/v1/admin/charges', {}, auth_header(user_id: admin_id, role: 'admin')
        meta = json_body['meta']
        expect(meta).to include('total', 'page', 'per_page')
        expect(meta['total']).to eq(2)
      end
    end

    context 'with status=paid filter' do
      it 'returns only paid charges' do
        get '/v1/admin/charges?status=paid', {}, auth_header(user_id: admin_id, role: 'admin')
        data = json_body['data']
        expect(data.length).to eq(1)
        expect(data.first['status']).to eq('paid')
      end

      it 'reflects the filtered total in meta' do
        get '/v1/admin/charges?status=paid', {}, auth_header(user_id: admin_id, role: 'admin')
        expect(json_body['meta']['total']).to eq(1)
      end
    end
  end

  describe 'GET /v1/admin/wallets' do
    before do
      create_wallet(user_id: 301, balance_cents: 10_000)
      create_wallet(user_id: 302, balance_cents: 5_000)
    end

    it 'returns 200' do
      get '/v1/admin/wallets', {}, auth_header(user_id: admin_id, role: 'admin')
      expect(last_response.status).to eq(200)
    end

    it 'returns total_balance_cents' do
      get '/v1/admin/wallets', {}, auth_header(user_id: admin_id, role: 'admin')
      expect(json_body['data']['total_balance_cents']).to eq(15_000)
    end

    it 'returns top_wallets array' do
      get '/v1/admin/wallets', {}, auth_header(user_id: admin_id, role: 'admin')
      top = json_body['data']['top_wallets']
      expect(top).to be_an(Array)
      expect(top.length).to eq(2)
    end

    it 'orders top_wallets by balance descending' do
      get '/v1/admin/wallets', {}, auth_header(user_id: admin_id, role: 'admin')
      top = json_body['data']['top_wallets']
      expect(top.first['balance_cents']).to eq(10_000)
      expect(top.last['balance_cents']).to eq(5_000)
    end

    it 'includes user_id and balance_cents in each wallet entry' do
      get '/v1/admin/wallets', {}, auth_header(user_id: admin_id, role: 'admin')
      entry = json_body['data']['top_wallets'].first
      expect(entry).to have_key('user_id')
      expect(entry).to have_key('balance_cents')
    end
  end
end
