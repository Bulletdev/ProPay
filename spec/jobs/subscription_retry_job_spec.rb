# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SubscriptionRetryJob do
  let(:user_id)  { '99' }
  let(:customer) { create_customer(owner_id: user_id, email: 'retry@propay.gg') }

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

  def create_past_due_subscription(payment_failures: 0)
    SubscriptionService.new(customer: customer).create!(plan_name: 'pro_monthly', trial_days: 0).tap do |sub|
      sub.update(status: 'past_due', payment_failures: payment_failures)
    end
  end

  describe '#perform' do
    context 'when subscription does not exist' do
      it 'does nothing and does not raise' do
        expect { described_class.new.perform(999_999) }.not_to raise_error
      end
    end

    context 'when subscription status is not past_due' do
      it 'does nothing' do
        sub = SubscriptionService.new(customer: customer).create!(plan_name: 'pro_monthly', trial_days: 0)
        sub.update(status: 'active')

        expect(PixChargeService).not_to receive(:new)
        described_class.new.perform(sub.id)
      end
    end

    context 'D+1 retry (payment_failures = 0)' do
      before { stub_openpix_success }

      it 'creates a charge and increments payment_failures to 1' do
        sub = create_past_due_subscription(payment_failures: 0)

        expect { described_class.new.perform(sub.id) }
          .to change { Charge.where(subscription_id: sub.id).count }.by(1)

        expect(sub.reload.payment_failures).to eq(1)
      end

      it 'uses idempotency_key retry_<id>_1' do
        sub = create_past_due_subscription(payment_failures: 0)
        described_class.new.perform(sub.id)

        charge = Charge.where(subscription_id: sub.id).first
        expect(charge.idempotency_key).to eq("retry_#{sub.id}_1")
      end
    end

    context 'D+2 retry (payment_failures = 1)' do
      before { stub_openpix_success }

      it 'creates a charge and increments payment_failures to 2' do
        sub = create_past_due_subscription(payment_failures: 1)

        expect { described_class.new.perform(sub.id) }
          .to change { Charge.where(subscription_id: sub.id).count }.by(1)

        expect(sub.reload.payment_failures).to eq(2)
      end

      it 'uses idempotency_key retry_<id>_2' do
        sub = create_past_due_subscription(payment_failures: 1)
        described_class.new.perform(sub.id)

        charge = Charge.where(subscription_id: sub.id).first
        expect(charge.idempotency_key).to eq("retry_#{sub.id}_2")
      end
    end

    context 'D+3 retry (payment_failures = 2)' do
      before { stub_openpix_success }

      it 'creates a charge and increments payment_failures to 3' do
        sub = create_past_due_subscription(payment_failures: 2)

        expect { described_class.new.perform(sub.id) }
          .to change { Charge.where(subscription_id: sub.id).count }.by(1)

        expect(sub.reload.payment_failures).to eq(3)
      end

      it 'uses idempotency_key retry_<id>_3' do
        sub = create_past_due_subscription(payment_failures: 2)
        described_class.new.perform(sub.id)

        charge = Charge.where(subscription_id: sub.id).first
        expect(charge.idempotency_key).to eq("retry_#{sub.id}_3")
      end
    end

    context 'cancellation after MAX_FAILURES (payment_failures = 3)' do
      before { allow(TierSyncJob).to receive(:perform_async) }

      it 'cancels the subscription without creating a charge' do
        sub = create_past_due_subscription(payment_failures: 3)

        expect { described_class.new.perform(sub.id) }
          .not_to(change { Charge.where(subscription_id: sub.id).count })

        sub.reload
        expect(sub.status).to eq('cancelled')
        expect(sub.cancelled_at).not_to be_nil
      end

      it 'enqueues TierSyncJob with nil tier to downgrade the customer' do
        sub = create_past_due_subscription(payment_failures: 3)

        expect(TierSyncJob).to receive(:perform_async).with(user_id, nil)
        described_class.new.perform(sub.id)
      end
    end

    context 'idempotency: duplicate retry does not create a second charge' do
      before { stub_openpix_success }

      it 'skips charge creation when the same idempotency_key already exists' do
        sub = create_past_due_subscription(payment_failures: 0)
        described_class.new.perform(sub.id)

        Subscription.where(id: sub.id).update(payment_failures: 0, status: 'past_due')

        expect { described_class.new.perform(sub.id) }
          .not_to(change { Charge.where(subscription_id: sub.id).count })
      end
    end
  end
end
