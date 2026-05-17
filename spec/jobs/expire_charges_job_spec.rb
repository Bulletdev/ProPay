# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ExpireChargesJob do
  let(:user_id)  { '77' }
  let(:customer) { create_customer(owner_id: user_id, email: 'expire@propay.gg') }

  def create_active_charge(reference_type: 'wallet_deposit', subscription_id: nil, expires_at: Time.now.utc - 3600)
    Charge.create(
      customer_id: customer.id,
      subscription_id: subscription_id,
      txid: SecureRandom.hex(16),
      provider: 'openpix',
      provider_id: SecureRandom.hex(8),
      amount_cents: 1000,
      status: 'active',
      qr_code: 'some-brcode',
      qr_code_url: 'https://openpix.com.br/pay/test',
      reference_type: reference_type,
      reference_id: user_id,
      expires_at: expires_at,
      idempotency_key: SecureRandom.hex(16),
      metadata: Sequel.pg_json_wrap({})
    )
  end

  def create_active_subscription
    Subscription.create(
      customer_id: customer.id,
      plan_name: 'pro_monthly',
      status: 'active',
      amount_cents: 4900,
      interval: 'month',
      current_period_start: Time.now.utc - (30 * 86_400),
      current_period_end: Time.now.utc - 3600,
      next_charge_at: Time.now.utc - 3600,
      payment_failures: 0
    )
  end

  before do
    allow(SubscriptionRetryJob).to receive(:perform_in)
  end

  describe '#perform' do
    context 'charge expiration' do
      it 'marks active charges with past expires_at as expired' do
        charge = create_active_charge(expires_at: Time.now.utc - 7200)
        described_class.new.perform
        expect(charge.reload.status).to eq('expired')
      end

      it 'does not touch charges that have not yet expired' do
        charge = create_active_charge(expires_at: Time.now.utc + 3600)
        described_class.new.perform
        expect(charge.reload.status).to eq('active')
      end

      it 'does not touch charges already in a terminal status' do
        charge = create_active_charge(expires_at: Time.now.utc - 7200)
        charge.update(status: 'paid')
        described_class.new.perform
        expect(charge.reload.status).to eq('paid')
      end
    end

    context 'subscription transition' do
      let!(:subscription) { create_active_subscription }

      it 'transitions subscription to past_due when its renewal charge expires' do
        create_active_charge(
          reference_type: 'subscription',
          subscription_id: subscription.id,
          expires_at: Time.now.utc - 3600
        )

        described_class.new.perform

        expect(subscription.reload.status).to eq('past_due')
      end

      it 'enqueues SubscriptionRetryJob D+1 for the subscription' do
        create_active_charge(
          reference_type: 'subscription',
          subscription_id: subscription.id,
          expires_at: Time.now.utc - 3600
        )

        described_class.new.perform

        expect(SubscriptionRetryJob).to have_received(:perform_in).with(86_400, subscription.id)
      end

      it 'does not transition subscriptions already in past_due' do
        subscription.update(status: 'past_due')
        create_active_charge(
          reference_type: 'subscription',
          subscription_id: subscription.id,
          expires_at: Time.now.utc - 3600
        )

        described_class.new.perform

        expect(subscription.reload.status).to eq('past_due')
        expect(SubscriptionRetryJob).not_to have_received(:perform_in)
      end

      it 'does not transition subscription for non-subscription charges' do
        create_active_charge(reference_type: 'wallet_deposit', expires_at: Time.now.utc - 3600)

        described_class.new.perform

        expect(subscription.reload.status).to eq('active')
        expect(SubscriptionRetryJob).not_to have_received(:perform_in)
      end

      it 'handles multiple expired subscription charges independently' do
        sub2 = Subscription.create(
          customer_id: customer.id,
          plan_name: 'pro_monthly',
          status: 'active',
          amount_cents: 4900,
          interval: 'month',
          current_period_start: Time.now.utc - (30 * 86_400),
          current_period_end: Time.now.utc - 3600,
          next_charge_at: Time.now.utc - 3600,
          payment_failures: 0
        )

        create_active_charge(
          reference_type: 'subscription',
          subscription_id: subscription.id,
          expires_at: Time.now.utc - 3600
        )
        create_active_charge(
          reference_type: 'subscription',
          subscription_id: sub2.id,
          expires_at: Time.now.utc - 3600
        )

        described_class.new.perform

        expect(subscription.reload.status).to eq('past_due')
        expect(sub2.reload.status).to eq('past_due')
        expect(SubscriptionRetryJob).to have_received(:perform_in).twice
      end
    end

    context 'when there are no expired charges' do
      it 'does nothing and does not raise' do
        create_active_charge(expires_at: Time.now.utc + 3600)
        expect { described_class.new.perform }.not_to raise_error
        expect(SubscriptionRetryJob).not_to have_received(:perform_in)
      end
    end
  end
end
