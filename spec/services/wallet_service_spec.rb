# frozen_string_literal: true

require 'spec_helper'

RSpec.describe WalletService do
  let(:user_id) { 42 }

  describe '.credit!' do
    let(:idempotency_key) { 'credit-key-001' }

    context 'when wallet does not exist' do
      it 'creates the wallet and credits the amount' do
        expect(Wallet.first(user_id: user_id)).to be_nil

        txn = described_class.credit!(
          user_id: user_id,
          amount_cents: 1000,
          type: 'deposit',
          description: 'First deposit',
          idempotency_key: idempotency_key
        )

        wallet = Wallet.first(user_id: user_id)
        expect(wallet).not_to be_nil
        expect(wallet.balance_cents).to eq(1000)
        expect(txn.amount_cents).to eq(1000)
        expect(txn.balance_after).to eq(1000)
      end
    end

    context 'when wallet already exists' do
      before { create_wallet(user_id: user_id, balance_cents: 500) }

      it 'adds the amount to the existing balance' do
        described_class.credit!(
          user_id: user_id,
          amount_cents: 300,
          type: 'deposit',
          description: 'Top-up',
          idempotency_key: idempotency_key
        )

        expect(Wallet.first(user_id: user_id).balance_cents).to eq(800)
      end

      it 'creates a wallet transaction record' do
        expect do
          described_class.credit!(
            user_id: user_id,
            amount_cents: 300,
            type: 'deposit',
            description: 'Top-up',
            idempotency_key: idempotency_key
          )
        end.to change { WalletTransaction.count }.by(1)
      end

      it 'records balance_after correctly on the transaction' do
        txn = described_class.credit!(
          user_id: user_id,
          amount_cents: 300,
          type: 'deposit',
          description: 'Top-up',
          idempotency_key: idempotency_key
        )

        expect(txn.balance_after).to eq(800)
      end
    end

    context 'idempotency' do
      before { create_wallet(user_id: user_id, balance_cents: 500) }

      it 'returns the existing transaction on a duplicate call' do
        first_txn = described_class.credit!(
          user_id: user_id,
          amount_cents: 200,
          type: 'deposit',
          description: 'Deposit',
          idempotency_key: idempotency_key
        )

        second_txn = described_class.credit!(
          user_id: user_id,
          amount_cents: 200,
          type: 'deposit',
          description: 'Deposit',
          idempotency_key: idempotency_key
        )

        expect(second_txn.id).to eq(first_txn.id)
      end

      it 'does not update the wallet balance on a duplicate call' do
        described_class.credit!(
          user_id: user_id,
          amount_cents: 200,
          type: 'deposit',
          description: 'Deposit',
          idempotency_key: idempotency_key
        )

        expect do
          described_class.credit!(
            user_id: user_id,
            amount_cents: 200,
            type: 'deposit',
            description: 'Deposit',
            idempotency_key: idempotency_key
          )
        end.not_to(change { Wallet.first(user_id: user_id).balance_cents })
      end
    end

    context 'with optional reference fields' do
      before { create_wallet(user_id: user_id, balance_cents: 0) }

      it 'stores reference_type and reference_id on the transaction' do
        txn = described_class.credit!(
          user_id: user_id,
          amount_cents: 500,
          type: 'prize_credit',
          description: 'Prize payout',
          idempotency_key: idempotency_key,
          reference_type: 'charge',
          reference_id: 99
        )

        expect(txn.reference_type).to eq('charge')
        expect(txn.reference_id).to eq(99)
      end
    end
  end

  describe '.debit!' do
    let(:idempotency_key) { 'debit-key-001' }

    context 'when the wallet has sufficient funds' do
      before { create_wallet(user_id: user_id, balance_cents: 1000) }

      it 'deducts the amount from the balance' do
        described_class.debit!(
          user_id: user_id,
          amount_cents: 400,
          type: 'inscription_debit',
          description: 'Tournament entry',
          idempotency_key: idempotency_key
        )

        expect(Wallet.first(user_id: user_id).balance_cents).to eq(600)
      end

      it 'creates a transaction with negative amount_cents' do
        txn = described_class.debit!(
          user_id: user_id,
          amount_cents: 400,
          type: 'inscription_debit',
          description: 'Tournament entry',
          idempotency_key: idempotency_key
        )

        expect(txn.amount_cents).to eq(-400)
      end

      it 'records the correct balance_after' do
        txn = described_class.debit!(
          user_id: user_id,
          amount_cents: 400,
          type: 'inscription_debit',
          description: 'Tournament entry',
          idempotency_key: idempotency_key
        )

        expect(txn.balance_after).to eq(600)
      end
    end

    context 'when the wallet has insufficient funds' do
      before { create_wallet(user_id: user_id, balance_cents: 100) }

      it 'raises InsufficientFunds' do
        expect do
          described_class.debit!(
            user_id: user_id,
            amount_cents: 500,
            type: 'inscription_debit',
            description: 'Too expensive',
            idempotency_key: idempotency_key
          )
        end.to raise_error(WalletService::InsufficientFunds)
      end

      it 'does not modify the wallet balance' do
        expect do
          described_class.debit!(
            user_id: user_id,
            amount_cents: 500,
            type: 'inscription_debit',
            description: 'Too expensive',
            idempotency_key: idempotency_key
          )
        end.to raise_error(WalletService::InsufficientFunds)
          .and(not_change { Wallet.first(user_id: user_id).balance_cents })
      end
    end

    context 'when the wallet does not exist' do
      it 'raises InsufficientFunds' do
        expect do
          described_class.debit!(
            user_id: user_id,
            amount_cents: 100,
            type: 'inscription_debit',
            description: 'No wallet',
            idempotency_key: idempotency_key
          )
        end.to raise_error(WalletService::InsufficientFunds)
      end
    end
  end
end
