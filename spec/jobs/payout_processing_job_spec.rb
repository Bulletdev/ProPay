# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PayoutProcessingJob do
  let(:user_id)      { 50 }
  let(:wallet)       { create_wallet(user_id: user_id, balance_cents: 100_000) }
  let(:valid_cpf)    { '12345678901' }

  def create_payout(wallet_id:, amount_cents: 10_000, status: 'pending',
                    pix_key_type: 'cpf', pix_key: valid_cpf)
    Payout.create(
      wallet_id: wallet_id,
      amount_cents: amount_cents,
      status: status,
      pix_key_type: pix_key_type,
      pix_key: pix_key
    )
  end

  def seed_old_deposit(wallet_id:)
    WalletTransaction.create(
      wallet_id: wallet_id,
      amount_cents: 100_000,
      type: 'deposit',
      description: 'Old deposit',
      balance_after: 100_000,
      idempotency_key: "seed-deposit-#{wallet_id}-#{SecureRandom.hex(4)}",
      created_at: Time.now.utc - (25 * 3600)
    )
  end

  describe '#perform' do
    context 'when payout does not exist' do
      it 'returns without raising an error' do
        expect { described_class.new.perform(999_999) }.not_to raise_error
      end
    end

    context 'when payout status is not pending' do
      let!(:payout) do
        wallet
        create_payout(wallet_id: wallet.id, status: 'completed')
      end

      it 'returns without modifying the payout' do
        expect { described_class.new.perform(payout.id) }.not_to raise_error
        expect(payout.reload.status).to eq('completed')
      end
    end

    context 'when the wallet is not found' do
      let!(:payout) do
        create_payout(wallet_id: wallet.id, status: 'pending')
      end

      before { wallet.delete }

      it 'sets the payout status to failed' do
        described_class.new.perform(payout.id)
        expect(payout.reload.status).to eq('failed')
      end

      it 'records wallet not found as the failure reason' do
        described_class.new.perform(payout.id)
        expect(payout.reload.failure_reason).to include('wallet not found')
      end
    end

    context 'when the wallet has insufficient funds' do
      let!(:payout) do
        wallet
        seed_old_deposit(wallet_id: wallet.id)
        create_payout(wallet_id: wallet.id, amount_cents: wallet.balance_cents + 1)
      end

      it 'sets the payout status to failed' do
        described_class.new.perform(payout.id)
        expect(payout.reload.status).to eq('failed')
      end

      it 'records insufficient funds as the failure reason' do
        described_class.new.perform(payout.id)
        expect(payout.reload.failure_reason).to include('insufficient funds')
      end

      it 'does not modify the wallet balance' do
        original_balance = wallet.balance_cents
        described_class.new.perform(payout.id)
        expect(wallet.reload.balance_cents).to eq(original_balance)
      end
    end

    context 'when the PIX key is invalid' do
      let!(:payout) do
        wallet
        seed_old_deposit(wallet_id: wallet.id)
        create_payout(wallet_id: wallet.id, pix_key_type: 'cpf', pix_key: 'invalido')
      end

      it 'sets the payout status to failed' do
        described_class.new.perform(payout.id)
        expect(payout.reload.status).to eq('failed')
      end

      it 'records invalid pix key as the failure reason' do
        described_class.new.perform(payout.id)
        expect(payout.reload.failure_reason).to include('invalid pix key')
      end
    end

    context 'when anti-fraud: deposit was made less than 24 hours ago' do
      let!(:payout) do
        wallet
        WalletTransaction.create(
          wallet_id: wallet.id,
          amount_cents: 100_000,
          type: 'deposit',
          description: 'Recent deposit',
          balance_after: 100_000,
          idempotency_key: "recent-deposit-#{SecureRandom.hex(4)}",
          created_at: Time.now.utc - (23 * 3600)
        )
        create_payout(wallet_id: wallet.id, amount_cents: 10_000)
      end

      it 'sets the payout status to failed' do
        described_class.new.perform(payout.id)
        expect(payout.reload.status).to eq('failed')
      end

      it 'records the anti-fraud reason in failure_reason' do
        described_class.new.perform(payout.id)
        expect(payout.reload.failure_reason).to include('anti-fraud')
      end
    end

    context 'when all conditions are met' do
      let!(:payout) do
        wallet
        seed_old_deposit(wallet_id: wallet.id)
        create_payout(wallet_id: wallet.id, amount_cents: 10_000)
      end

      it 'sets the payout status to completed' do
        described_class.new.perform(payout.id)
        expect(payout.reload.status).to eq('completed')
      end

      it 'debits the wallet by the payout amount' do
        original_balance = wallet.reload.balance_cents
        described_class.new.perform(payout.id)
        expect(wallet.reload.balance_cents).to eq(original_balance - 10_000)
      end

      it 'sets provider_transfer_id on the payout' do
        described_class.new.perform(payout.id)
        expect(payout.reload.provider_transfer_id).to be_present
      end

      it 'sets completed_at on the payout' do
        before_time = Time.now.utc
        described_class.new.perform(payout.id)
        expect(payout.reload.completed_at).to be >= before_time
      end
    end

    context 'idempotency' do
      let!(:payout) do
        wallet
        seed_old_deposit(wallet_id: wallet.id)
        create_payout(wallet_id: wallet.id, amount_cents: 10_000)
      end

      before { described_class.new.perform(payout.id) }

      it 'is a no-op when executed a second time on a completed payout' do
        balance_after_first = wallet.reload.balance_cents
        described_class.new.perform(payout.id)
        expect(wallet.reload.balance_cents).to eq(balance_after_first)
      end

      it 'leaves the payout status as completed on the second execution' do
        described_class.new.perform(payout.id)
        expect(payout.reload.status).to eq('completed')
      end
    end
  end
end
