# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PixChargeService do
  let(:customer)        { create_customer(owner_id: 10) }
  let(:service)         { described_class.new(customer: customer) }
  let(:idempotency_key) { 'pix-idem-001' }
  let(:txid)            { 'abc123def456abc123def456abc123de' }

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
  end

  describe '#create!' do
    it 'returns a charge with status active' do
      charge = service.create!(
        amount_cents: 2000,
        description: 'Test charge',
        reference_type: 'wallet_deposit',
        reference_id: 10,
        expires_in_seconds: 3600,
        idempotency_key: idempotency_key
      )

      expect(charge.status).to eq('active')
    end

    it 'persists the charge to the database' do
      expect do
        service.create!(
          amount_cents: 2000,
          description: 'Test charge',
          reference_type: 'wallet_deposit',
          reference_id: 10,
          expires_in_seconds: 3600,
          idempotency_key: idempotency_key
        )
      end.to change { Charge.count }.by(1)
    end

    it 'stores the qr_code returned by OpenPix' do
      charge = service.create!(
        amount_cents: 2000,
        description: 'Test charge',
        reference_type: 'wallet_deposit',
        reference_id: 10,
        expires_in_seconds: 3600,
        idempotency_key: idempotency_key
      )

      expect(charge.qr_code).to eq('00020126580014br.gov.bcb.brcode...')
    end

    it 'stores the qr_code_url returned by OpenPix' do
      charge = service.create!(
        amount_cents: 2000,
        description: 'Test charge',
        reference_type: 'wallet_deposit',
        reference_id: 10,
        expires_in_seconds: 3600,
        idempotency_key: idempotency_key
      )

      expect(charge.qr_code_url).to eq('https://openpix.com.br/pay/test')
    end

    it 'associates the charge with the correct customer' do
      charge = service.create!(
        amount_cents: 2000,
        description: 'Test charge',
        reference_type: 'wallet_deposit',
        reference_id: 10,
        expires_in_seconds: 3600,
        idempotency_key: idempotency_key
      )

      expect(charge.customer_id).to eq(customer.id)
    end

    context 'idempotency' do
      it 'returns the existing charge without calling OpenPix on a duplicate key' do
        first_charge = service.create!(
          amount_cents: 2000,
          description: 'Test charge',
          reference_type: 'wallet_deposit',
          reference_id: 10,
          expires_in_seconds: 3600,
          idempotency_key: idempotency_key
        )

        second_charge = service.create!(
          amount_cents: 2000,
          description: 'Test charge',
          reference_type: 'wallet_deposit',
          reference_id: 10,
          expires_in_seconds: 3600,
          idempotency_key: idempotency_key
        )

        expect(second_charge.id).to eq(first_charge.id)
        expect(WebMock).to have_requested(:post, 'https://api.openpix.com.br/api/v1/charge').once
      end

      it 'does not create a second charge record on duplicate key' do
        2.times do
          service.create!(
            amount_cents: 2000,
            description: 'Test charge',
            reference_type: 'wallet_deposit',
            reference_id: 10,
            expires_in_seconds: 3600,
            idempotency_key: idempotency_key
          )
        end

        expect(Charge.where(idempotency_key: idempotency_key).count).to eq(1)
      end
    end

    context 'when OpenPix returns a non-200 status' do
      before do
        stub_request(:post, 'https://api.openpix.com.br/api/v1/charge')
          .to_return(status: 500, body: '{"error":"internal"}')
      end

      it 'raises a RuntimeError' do
        expect do
          service.create!(
            amount_cents: 2000,
            description: 'Test charge',
            reference_type: 'wallet_deposit',
            reference_id: 10,
            expires_in_seconds: 3600,
            idempotency_key: idempotency_key
          )
        end.to raise_error(RuntimeError, /OpenPix API error/)
      end

      it 'does not persist a charge on API failure' do
        expect do
          service.create!(
            amount_cents: 2000,
            description: 'Test charge',
            reference_type: 'wallet_deposit',
            reference_id: 10,
            expires_in_seconds: 3600,
            idempotency_key: idempotency_key
          )
        end.to raise_error(RuntimeError).and(not_change { Charge.count })
      end
    end
  end

  describe '#cancel!' do
    let!(:charge) do
      Charge.create(
        customer_id: customer.id,
        txid: txid,
        provider: 'openpix',
        provider_id: txid,
        amount_cents: 1500,
        status: 'active',
        qr_code: 'some-brcode',
        qr_code_url: 'https://openpix.com.br/pay/test',
        reference_type: 'wallet_deposit',
        reference_id: 10,
        expires_at: Time.now.utc + 3600,
        idempotency_key: idempotency_key,
        metadata: Sequel.pg_json_wrap({})
      )
    end

    before do
      stub_request(:delete, "https://api.openpix.com.br/api/v1/charge/#{txid}")
        .to_return(status: 200, body: '{}')
    end

    it 'updates the charge status to cancelled' do
      service.cancel!(txid: txid)
      expect(charge.reload.status).to eq('cancelled')
    end

    it 'returns the updated charge' do
      result = service.cancel!(txid: txid)
      expect(result.txid).to eq(txid)
      expect(result.status).to eq('cancelled')
    end

    context 'when the charge does not exist for the customer' do
      it 'raises ArgumentError' do
        other_customer = create_customer(owner_id: 99, email: 'other@propay.gg')
        other_service  = described_class.new(customer: other_customer)

        expect do
          other_service.cancel!(txid: txid)
        end.to raise_error(ArgumentError, /charge not found/)
      end
    end

    context 'when the charge is not active' do
      before { charge.update(status: 'cancelled') }

      it 'raises ArgumentError' do
        expect do
          service.cancel!(txid: txid)
        end.to raise_error(ArgumentError, /not cancellable/)
      end
    end

    context 'when the charge is paid' do
      before { charge.update(status: 'paid') }

      it 'raises ArgumentError' do
        expect do
          service.cancel!(txid: txid)
        end.to raise_error(ArgumentError, /not cancellable/)
      end
    end
  end
end
