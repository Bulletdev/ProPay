# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RecurringChargeJob do
  let(:user_id)   { 42 }
  let(:customer)  { create_customer(owner_id: user_id, email: 'recurring@propay.gg') }

  let(:openpix_success_body) do
    Oj.dump({
              'charge' => {
                'correlationID' => SecureRandom.hex(16),
                'brCode' => '00020126580014br.gov.bcb.brcode...',
                'paymentLinkUrl' => 'https://openpix.com.br/pay/test'
              }
            }, mode: :compat)
  end

  def stub_openpix_success
    stub_request(:post, 'https://api.openpix.com.br/api/v1/charge')
      .to_return(
        status: 200,
        body: openpix_success_body,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def build_subscription(next_charge_at:)
    SubscriptionService.new(customer: customer).create!(plan_name: 'pro_monthly', trial_days: 0).tap do |sub|
      sub.update(status: 'active', next_charge_at: next_charge_at)
    end
  end

  describe '#perform' do
    context 'when no subscriptions have a due next_charge_at' do
      it 'does nothing' do
        customer
        build_subscription(next_charge_at: Time.now.utc + 3600)

        expect(PixChargeService).not_to receive(:new)
        described_class.new.perform
      end
    end

    context 'when a subscription has next_charge_at in the past' do
      before { stub_openpix_success }

      it 'creates a charge for the subscription' do
        customer
        sub = build_subscription(next_charge_at: Time.now.utc - 60)

        expect { described_class.new.perform }.to change { Charge.where(subscription_id: sub.id).count }.by(1)
      end
    end

    context 'when a subscription has next_charge_at in the future' do
      it 'does not create a charge' do
        customer
        sub = build_subscription(next_charge_at: Time.now.utc + 7200)

        expect { described_class.new.perform }.not_to(change { Charge.where(subscription_id: sub.id).count })
      end
    end

    context 'when charge creation raises an error' do
      it 'logs the error and does not propagate the exception' do
        customer
        build_subscription(next_charge_at: Time.now.utc - 60)

        allow_any_instance_of(PixChargeService).to receive(:create!).and_raise(StandardError, 'provider timeout')

        expect(Sidekiq.logger).to receive(:error).with(/provider timeout/)
        expect { described_class.new.perform }.not_to raise_error
      end
    end

    context 'idempotency via idempotency_key' do
      before { stub_openpix_success }

      it 'does not create a duplicate charge when the same key already exists' do
        customer
        sub = build_subscription(next_charge_at: Time.now.utc - 60)
        expected_key = "recurring_#{sub.id}_#{sub.next_charge_at.to_i}"

        Charge.create(
          customer_id: customer.id,
          txid: SecureRandom.hex(16),
          provider: 'openpix',
          provider_id: 'existing-provider-id',
          amount_cents: 4900,
          status: 'active',
          qr_code: 'some-brcode',
          qr_code_url: 'https://openpix.com.br/pay/existing',
          reference_type: 'subscription',
          reference_id: sub.id,
          subscription_id: sub.id,
          expires_at: Time.now.utc + 86_400,
          idempotency_key: expected_key,
          metadata: Sequel.pg_json_wrap({})
        )

        expect { described_class.new.perform }.not_to(change { Charge.count })
      end
    end
  end
end
