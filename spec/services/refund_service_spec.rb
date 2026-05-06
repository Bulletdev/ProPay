# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RefundService do
  let(:customer) { create_customer }
  let(:wallet)   { create_wallet(user_id: customer.owner_id, balance_cents: 10_000) }
  let(:paid_charge) do
    Charge.create(
      customer_id: customer.id,
      txid: SecureRandom.hex(16),
      provider: 'openpix',
      amount_cents: 5_000,
      status: 'paid',
      expires_at: Time.now.utc + 3600,
      paid_at: Time.now.utc - 3600,
      idempotency_key: SecureRandom.hex(8),
      metadata: Sequel.pg_json_wrap({})
    )
  end

  before { wallet }

  describe '#refund_to_wallet!' do
    subject(:service) { described_class.new(charge: paid_charge) }

    it 'marks charge as refunded' do
      service.refund_to_wallet!(idempotency_key: 'ref_001')
      expect(paid_charge.reload.status).to eq('refunded')
    end

    it 'credits the wallet' do
      expect do
        service.refund_to_wallet!(idempotency_key: 'ref_001')
      end.to change { Wallet.first(user_id: customer.owner_id).balance_cents }.by(5_000)
    end

    it 'is idempotent' do
      service.refund_to_wallet!(idempotency_key: 'ref_001')
      expect do
        service.refund_to_wallet!(idempotency_key: 'ref_001')
      end.not_to(change { Wallet.first(user_id: customer.owner_id).balance_cents })
    end

    context 'when charge is not paid' do
      before { paid_charge.update(status: 'active') }

      it 'raises ChargeNotRefundable' do
        expect do
          service.refund_to_wallet!(idempotency_key: 'ref_002')
        end.to raise_error(RefundService::ChargeNotRefundable)
      end
    end

    context 'when outside CDC window' do
      before { paid_charge.update(paid_at: Time.now.utc - (8 * 86_400)) }

      it 'raises OutsideCdcWindow' do
        expect do
          service.refund_to_wallet!(idempotency_key: 'ref_003')
        end.to raise_error(RefundService::OutsideCdcWindow)
      end
    end
  end
end
