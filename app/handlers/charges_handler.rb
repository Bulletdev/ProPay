# frozen_string_literal: true

class ChargesHandler
  def initialize(request, auth)
    @r    = request
    @auth = auth
  end

  def call
    @r.post do
      body            = parse_body
      idempotency_key = require_idempotency_key!

      result = ChargeValidator.new.call(body)
      if result.failure?
        @r.halt(422,
                Oj.dump({ error: 'validation_failed', errors: result.errors.to_h }, mode: :compat))
      end

      customer = find_customer!

      service = PixChargeService.new(customer: customer)
      charge  = service.create!(
        amount_cents: Integer(body['amount_cents']),
        description: body['description'].to_s,
        reference_type: body['reference_type'],
        reference_id: body['reference_id']&.to_i,
        expires_in_seconds: Integer(body.fetch('expires_in_seconds', 3600)),
        idempotency_key: idempotency_key
      )

      response.status = 201
      Oj.dump({ data: serialize(charge) }, mode: :compat)
    end

    @r.on ':txid' do |txid|
      @r.get do
        customer = find_customer!
        charge   = Charge.first(txid: txid, customer_id: customer.id)
        @r.halt(404, Oj.dump({ error: 'not_found' }, mode: :compat)) unless charge
        Oj.dump({ data: serialize(charge) }, mode: :compat)
      end

      @r.delete do
        customer = find_customer!
        service  = PixChargeService.new(customer: customer)
        charge   = service.cancel!(txid: txid)
        Oj.dump({ data: serialize(charge) }, mode: :compat)
      rescue ArgumentError => e
        @r.halt(422, Oj.dump({ error: e.message }, mode: :compat))
      end

      @r.on 'refund' do
        @r.post do
          idempotency_key = require_idempotency_key!
          customer        = find_customer!
          charge          = Charge.first(txid: txid, customer_id: customer.id)
          @r.halt(404, Oj.dump({ error: 'charge not found' }, mode: :compat)) unless charge

          service = RefundService.new(charge: charge)
          service.refund_to_wallet!(idempotency_key: idempotency_key)
          Oj.dump({ data: { txid: charge.txid, status: 'refunded' } }, mode: :compat)
        rescue RefundService::ChargeNotRefundable, RefundService::OutsideCdcWindow => e
          @r.halt(422, Oj.dump({ error: e.message }, mode: :compat))
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

  def serialize(charge)
    {
      txid: charge.txid,
      status: charge.status,
      amount_cents: charge.amount_cents,
      qr_code: charge.qr_code,
      qr_code_url: charge.qr_code_url,
      expires_at: charge.expires_at&.iso8601,
      paid_at: charge.paid_at&.iso8601
    }
  end
end
