# frozen_string_literal: true

class WalletHandler
  def initialize(request, auth)
    @r    = request
    @auth = auth
  end

  def call
    @r.get do
      wallet = Wallet.first(user_id: @auth.user_id)
      Oj.dump({ data: { balance_cents: wallet&.balance_cents || 0 } }, mode: :compat)
    end

    @r.on 'transactions' do
      @r.get do
        wallet = Wallet.first(user_id: @auth.user_id)
        txns   = wallet ? transactions_for(wallet) : []
        Oj.dump({ data: txns }, mode: :compat)
      end
    end

    @r.on 'deposit' do
      @r.post do
        body            = parse_body
        idempotency_key = require_idempotency_key!
        customer        = find_customer!

        service = PixChargeService.new(customer: customer)
        charge  = service.create!(
          amount_cents: Integer(body['amount_cents']),
          description: 'Wallet deposit via PIX',
          reference_type: 'wallet_deposit',
          reference_id: @auth.user_id,
          expires_in_seconds: 3600,
          idempotency_key: idempotency_key
        )
        @r.response.status = 201
        Oj.dump({
                  data: {
                    txid: charge.txid,
                    qr_code: charge.qr_code,
                    qr_code_url: charge.qr_code_url,
                    expires_at: charge.expires_at&.iso8601
                  }
                }, mode: :compat)
      end
    end

    @r.on 'debit' do
      @r.post do
        body            = parse_body
        idempotency_key = require_idempotency_key!

        WalletService.debit!(
          user_id: @auth.user_id,
          amount_cents: Integer(body['amount_cents']),
          type: 'inscription_debit',
          description: body.fetch('description', 'Tournament inscription'),
          idempotency_key: idempotency_key,
          reference_type: body['reference_type'],
          reference_id: body['reference_id']&.to_i
        )
        wallet = Wallet.first(user_id: @auth.user_id)
        Oj.dump({ data: { balance_cents: wallet.balance_cents } }, mode: :compat)
      rescue WalletService::InsufficientFunds
        @r.halt(422, Oj.dump({ error: 'insufficient_funds' }, mode: :compat))
      end
    end

    @r.on 'payouts' do
      @r.post do
        body            = parse_body
        idempotency_key = require_idempotency_key!

        pix_key_type = body['pix_key_type'].to_s
        pix_key      = body['pix_key'].to_s
        amount_cents = body['amount_cents'].to_i

        unless PixKeyValidator.valid_type?(pix_key_type)
          @r.halt(422,
                  Oj.dump({ error: 'invalid_pix_key_type', valid_types: PixKeyValidator::VALIDATORS.keys },
                          mode: :compat))
        end

        unless PixKeyValidator.valid?(pix_key_type, pix_key)
          @r.halt(422, Oj.dump({ error: 'invalid_pix_key', type: pix_key_type }, mode: :compat))
        end

        wallet = Wallet.first(user_id: @auth.user_id)
        unless wallet&.sufficient_funds?(amount_cents)
          @r.halt(422, Oj.dump({ error: 'insufficient_funds' }, mode: :compat))
        end

        existing_tx = WalletTransaction.first(idempotency_key: "payout_debit_#{idempotency_key}")
        if existing_tx
          existing_payout = Payout.first(wallet_id: wallet.id, status: %w[pending processing completed])
          @r.halt(200, Oj.dump({ data: serialize_payout(existing_payout) }, mode: :compat)) if existing_payout
        end

        payout = Payout.create(
          wallet_id: wallet.id,
          amount_cents: amount_cents,
          pix_key: pix_key,
          pix_key_type: pix_key_type,
          status: 'pending'
        )

        PayoutProcessingJob.perform_async(payout.id)

        @r.response.status = 202
        Oj.dump({ data: serialize_payout(payout) }, mode: :compat)
      end

      @r.on ':payout_id' do |payout_id|
        @r.get do
          wallet = Wallet.first(user_id: @auth.user_id)
          @r.halt(404, Oj.dump({ error: 'not_found' }, mode: :compat)) unless wallet

          payout = Payout.first(id: Integer(payout_id), wallet_id: wallet.id)
          @r.halt(404, Oj.dump({ error: 'not_found' }, mode: :compat)) unless payout

          Oj.dump({ data: serialize_payout(payout) }, mode: :compat)
        end
      end
    end
  end

  private

  def parse_body
    Oj.load(@r.body.read, mode: :compat) || {}
  end

  def require_idempotency_key!
    key = @r.env['HTTP_IDEMPOTENCY_KEY']
    @r.halt(422, Oj.dump({ error: 'Idempotency-Key header required' }, mode: :compat)) unless key
    key
  end

  def find_customer!
    c = Customer.first(owner_type: 'user', owner_id: @auth.user_id)
    @r.halt(404, Oj.dump({ error: 'customer not found' }, mode: :compat)) unless c
    c
  end

  def serialize_payout(payout)
    {
      id: payout.id,
      amount_cents: payout.amount_cents,
      pix_key_type: payout.pix_key_type,
      status: payout.status,
      provider_transfer_id: payout.provider_transfer_id,
      completed_at: payout.completed_at&.iso8601,
      failed_at: payout.failed_at&.iso8601,
      failure_reason: payout.failure_reason,
      created_at: payout.created_at.iso8601
    }
  end

  def transactions_for(wallet)
    WalletTransaction
      .where(wallet_id: wallet.id)
      .order(Sequel.desc(:created_at))
      .limit(50)
      .map do |t|
        {
          id: t.id,
          amount_cents: t.amount_cents,
          type: t.type,
          description: t.description,
          balance_after: t.balance_after,
          reference_type: t.reference_type,
          reference_id: t.reference_id,
          created_at: t.created_at.iso8601
        }
      end
  end
end
