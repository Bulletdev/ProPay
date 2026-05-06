# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SubscriptionService do
  let(:customer) { create_customer(owner_id: 5) }
  let(:service)  { described_class.new(customer: customer) }

  describe '#create!' do
    context 'with a valid plan and trial_days > 0' do
      it 'creates a subscription with status trialing' do
        sub = service.create!(plan_name: 'pro_monthly', trial_days: 14)
        expect(sub.status).to eq('trialing')
      end

      it 'sets trial_ends_at to now + trial_days seconds' do
        freeze_time = Time.now.utc
        allow(Time).to receive(:now).and_return(freeze_time)

        sub = service.create!(plan_name: 'pro_monthly', trial_days: 14)
        expected_trial_end = freeze_time + (14 * 86_400)
        expect(sub.trial_ends_at.to_i).to be_within(2).of(expected_trial_end.to_i)
      end

      it 'persists the subscription to the database' do
        expect do
          service.create!(plan_name: 'pro_monthly', trial_days: 14)
        end.to change { Subscription.count }.by(1)
      end

      it 'stores the correct amount_cents for pro_monthly' do
        sub = service.create!(plan_name: 'pro_monthly', trial_days: 14)
        expect(sub.amount_cents).to eq(4900)
      end

      it 'stores the correct amount_cents for pro_annual' do
        sub = service.create!(plan_name: 'pro_annual', trial_days: 14)
        expect(sub.amount_cents).to eq(47_000)
      end
    end

    context 'with trial_days = 0' do
      it 'creates a subscription with status active' do
        sub = service.create!(plan_name: 'pro_monthly', trial_days: 0)
        expect(sub.status).to eq('active')
      end

      it 'does not set trial_ends_at' do
        sub = service.create!(plan_name: 'pro_monthly', trial_days: 0)
        expect(sub.trial_ends_at).to be_nil
      end
    end

    context 'with an invalid plan name' do
      it 'raises ArgumentError' do
        expect do
          service.create!(plan_name: 'nonexistent_plan')
        end.to raise_error(ArgumentError, /invalid plan/)
      end

      it 'does not create any subscription record' do
        expect do
          service.create!(plan_name: 'nonexistent_plan')
        end.to raise_error(ArgumentError).and(not_change { Subscription.count })
      end
    end

    context 'when the customer already has an active subscription' do
      let!(:existing_sub) do
        Subscription.create(
          customer_id: customer.id,
          plan_name: 'pro_monthly',
          status: 'active',
          amount_cents: 4900,
          interval: 'month',
          current_period_start: Time.now.utc,
          current_period_end: Time.now.utc + (30 * 86_400),
          next_charge_at: Time.now.utc + (30 * 86_400),
          payment_failures: 0
        )
      end

      it 'returns the existing subscription without creating a new one' do
        result = service.create!(plan_name: 'pro_annual')
        expect(result.id).to eq(existing_sub.id)
      end

      it 'does not create an additional subscription record' do
        expect do
          service.create!(plan_name: 'pro_annual')
        end.not_to(change { Subscription.count })
      end
    end

    context 'when the customer already has a trialing subscription' do
      let!(:existing_sub) do
        Subscription.create(
          customer_id: customer.id,
          plan_name: 'pro_monthly',
          status: 'trialing',
          amount_cents: 4900,
          interval: 'month',
          trial_ends_at: Time.now.utc + (14 * 86_400),
          current_period_start: Time.now.utc,
          current_period_end: Time.now.utc + (14 * 86_400),
          next_charge_at: Time.now.utc + (14 * 86_400),
          payment_failures: 0
        )
      end

      it 'returns the existing trialing subscription' do
        result = service.create!(plan_name: 'pro_monthly')
        expect(result.id).to eq(existing_sub.id)
      end
    end

    context 'enterprise plan' do
      it 'creates a subscription with amount_cents 0' do
        sub = service.create!(plan_name: 'enterprise', trial_days: 0)
        expect(sub.amount_cents).to eq(0)
      end
    end
  end

  describe '#cancel!' do
    before { allow(TierSyncJob).to receive(:perform_async) }
    let!(:active_sub) do
      Subscription.create(
        customer_id: customer.id,
        plan_name: 'pro_monthly',
        status: 'active',
        amount_cents: 4900,
        interval: 'month',
        current_period_start: Time.now.utc,
        current_period_end: Time.now.utc + (30 * 86_400),
        next_charge_at: Time.now.utc + (30 * 86_400),
        payment_failures: 0
      )
    end

    it 'changes the subscription status to cancelled' do
      service.cancel!(subscription_id: active_sub.id)
      expect(active_sub.reload.status).to eq('cancelled')
    end

    it 'sets ends_at to current_period_end' do
      service.cancel!(subscription_id: active_sub.id)
      expect(active_sub.reload.ends_at.to_i).to eq(active_sub.current_period_end.to_i)
    end

    it 'sets cancelled_at to a recent timestamp' do
      before_cancel = Time.now.utc
      service.cancel!(subscription_id: active_sub.id)
      expect(active_sub.reload.cancelled_at).to be >= before_cancel
    end

    it 'returns the updated subscription' do
      result = service.cancel!(subscription_id: active_sub.id)
      expect(result.id).to eq(active_sub.id)
      expect(result.status).to eq('cancelled')
    end

    context 'when the subscription does not belong to the customer' do
      let(:other_customer) { create_customer(owner_id: 99, email: 'other@propay.gg') }
      let(:other_service)  { described_class.new(customer: other_customer) }

      it 'raises ArgumentError' do
        expect do
          other_service.cancel!(subscription_id: active_sub.id)
        end.to raise_error(ArgumentError, 'subscription not found')
      end
    end

    context 'when the subscription does not exist' do
      it 'raises ArgumentError' do
        expect do
          service.cancel!(subscription_id: 999_999)
        end.to raise_error(ArgumentError, 'subscription not found')
      end
    end

    context 'when the subscription is already cancelled' do
      before { active_sub.update(status: 'cancelled') }

      it 'raises ArgumentError' do
        expect do
          service.cancel!(subscription_id: active_sub.id)
        end.to raise_error(ArgumentError, 'already cancelled')
      end
    end
  end
end
