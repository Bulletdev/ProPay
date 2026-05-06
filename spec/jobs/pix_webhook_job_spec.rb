# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PixWebhookJob do
  let(:user_id)    { 20 }
  let(:customer)   { create_customer(owner_id: user_id) }
  let(:end_to_end) { 'E00000000000000000000000000099' }
  let(:txid)       { 'ccddee001122334455667788aabbcc00' }

  let!(:charge) do
    Charge.create(
      customer_id: customer.id,
      txid: txid,
      provider: 'openpix',
      provider_id: txid,
      amount_cents: 5000,
      status: 'active',
      qr_code: 'some-brcode',
      qr_code_url: 'https://openpix.com.br/pay/test',
      reference_type: 'wallet_deposit',
      reference_id: user_id,
      expires_at: Time.now.utc + 3600,
      idempotency_key: 'charge-idem-job-01',
      metadata: Sequel.pg_json_wrap({})
    )
  end

  let(:base_payload) do
    {
      'event' => 'OPENPIX:CHARGE_COMPLETED',
      'charge' => { 'correlationID' => txid, 'value' => 5000 },
      'pix' => [{ 'endToEndId' => end_to_end }]
    }
  end

  def create_pending_event(payload = base_payload)
    WebhookEvent.create(
      provider: 'openpix',
      event_type: 'OPENPIX:CHARGE_COMPLETED',
      idempotency_key: end_to_end,
      status: 'pending',
      payload: Sequel.pg_json_wrap(payload),
      attempts: 0
    )
  end

  before do
    allow(TierSyncJob).to receive(:perform_async)
  end

  describe '#perform' do
    context 'wallet_deposit reference' do
      let!(:event) { create_pending_event }

      it 'credits the wallet with the charge amount' do
        described_class.new.perform(event.id)

        wallet = Wallet.first(user_id: user_id)
        expect(wallet).not_to be_nil
        expect(wallet.balance_cents).to eq(5000)
      end

      it 'marks the event as processed' do
        described_class.new.perform(event.id)
        expect(event.reload.status).to eq('processed')
      end

      it 'updates the charge status to paid' do
        described_class.new.perform(event.id)
        expect(charge.reload.status).to eq('paid')
      end

      it 'stores the end_to_end_id on the charge' do
        described_class.new.perform(event.id)
        expect(charge.reload.end_to_end_id).to eq(end_to_end)
      end

      it 'sets paid_at on the charge' do
        before_time = Time.now.utc
        described_class.new.perform(event.id)
        expect(charge.reload.paid_at).to be >= before_time
      end

      it 'increments the event attempts counter' do
        described_class.new.perform(event.id)
        expect(event.reload.attempts).to eq(1)
      end
    end

    context 'subscription reference' do
      let!(:subscription) do
        Subscription.create(
          customer_id: customer.id,
          plan_name: 'pro_monthly',
          status: 'trialing',
          amount_cents: 4900,
          interval: 'month',
          current_period_start: Time.now.utc,
          current_period_end: Time.now.utc + (14 * 86_400),
          next_charge_at: Time.now.utc + (14 * 86_400),
          payment_failures: 0
        )
      end

      let!(:sub_charge) do
        Charge.create(
          customer_id: customer.id,
          subscription_id: subscription.id,
          txid: 'sub-txid-001',
          provider: 'openpix',
          provider_id: 'sub-txid-001',
          amount_cents: 4900,
          status: 'active',
          qr_code: 'sub-brcode',
          qr_code_url: 'https://openpix.com.br/pay/sub',
          reference_type: 'subscription',
          reference_id: subscription.id,
          expires_at: Time.now.utc + 3600,
          idempotency_key: 'sub-charge-idem-01',
          metadata: Sequel.pg_json_wrap({})
        )
      end

      let(:sub_payload) do
        {
          'event' => 'OPENPIX:CHARGE_COMPLETED',
          'charge' => { 'correlationID' => 'sub-txid-001', 'value' => 4900 },
          'pix' => [{ 'endToEndId' => 'E00000000000000000000000000SUB' }]
        }
      end

      let!(:sub_event) do
        WebhookEvent.create(
          provider: 'openpix',
          event_type: 'OPENPIX:CHARGE_COMPLETED',
          idempotency_key: 'E00000000000000000000000000SUB',
          status: 'pending',
          payload: Sequel.pg_json_wrap(sub_payload),
          attempts: 0
        )
      end

      it 'activates the subscription' do
        described_class.new.perform(sub_event.id)
        expect(subscription.reload.status).to eq('active')
      end

      it 'resets payment_failures to 0' do
        subscription.update(payment_failures: 2)
        described_class.new.perform(sub_event.id)
        expect(subscription.reload.payment_failures).to eq(0)
      end

      it 'enqueues TierSyncJob with owner_id and plan_name' do
        described_class.new.perform(sub_event.id)
        expect(TierSyncJob).to have_received(:perform_async).with(user_id, 'pro_monthly')
      end
    end

    context 'when the charge is not found' do
      let(:bad_payload) do
        {
          'event' => 'OPENPIX:CHARGE_COMPLETED',
          'charge' => { 'correlationID' => 'nonexistent-txid' },
          'pix' => [{ 'endToEndId' => 'E00000000000000000000000000BAD' }]
        }
      end

      let!(:event) do
        WebhookEvent.create(
          provider: 'openpix',
          event_type: 'OPENPIX:CHARGE_COMPLETED',
          idempotency_key: 'E00000000000000000000000000BAD',
          status: 'pending',
          payload: Sequel.pg_json_wrap(bad_payload),
          attempts: 0
        )
      end

      it 'marks the event as failed' do
        described_class.new.perform(event.id)
        expect(event.reload.status).to eq('failed')
      end

      it 'sets an error_message on the event' do
        described_class.new.perform(event.id)
        expect(event.reload.error_message).to include('nonexistent-txid')
      end

      it 'does not raise an error' do
        expect { described_class.new.perform(event.id) }.not_to raise_error
      end
    end

    context 'idempotency' do
      let!(:event) { create_pending_event }

      before { described_class.new.perform(event.id) }

      it 'is a no-op when the event is already processed' do
        event.reload
        expect(event.status).to eq('processed')

        expect { described_class.new.perform(event.id) }.not_to(change { Wallet.first(user_id: user_id)&.balance_cents })
      end

      it 'does not re-enqueue or re-credit on repeat execution' do
        initial_balance = Wallet.first(user_id: user_id).balance_cents

        described_class.new.perform(event.id)

        expect(Wallet.first(user_id: user_id).balance_cents).to eq(initial_balance)
      end
    end

    context 'when the webhook event does not exist' do
      it 'does not raise an error' do
        expect { described_class.new.perform(999_999) }.not_to raise_error
      end
    end
  end
end
