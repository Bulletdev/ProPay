# frozen_string_literal: true

class SubscriptionsHandler
  def initialize(request, auth)
    @r    = request
    @auth = auth
  end

  def call
    @r.post do
      body     = parse_body
      customer = find_customer!
      service  = SubscriptionService.new(customer: customer)
      sub      = service.create!(
        plan_name: body['plan_name'].to_s,
        trial_days: Integer(body.fetch('trial_days', 14))
      )
      @r.response.status = 201
      Oj.dump({ data: serialize(sub) }, mode: :compat)
    rescue ArgumentError => e
      @r.halt(422, Oj.dump({ error: e.message }, mode: :compat))
    end

    @r.on 'by_owner' do
      @r.on :owner_id do |owner_id|
        @r.get do
          customer = Customer.first(owner_type: 'user', owner_id: Integer(owner_id))
          sub = customer && Subscription
                .where(customer_id: customer.id)
                .order(Sequel.desc(:created_at))
                .first
          Oj.dump({ data: sub ? serialize(sub) : nil }, mode: :compat)
        end
      end
    end

    @r.on :id do |id|
      @r.get do
        customer = find_customer!
        sub = Subscription.first(id: Integer(id), customer_id: customer.id)
        @r.halt(404, Oj.dump({ error: 'not_found' }, mode: :compat)) unless sub
        Oj.dump({ data: serialize(sub) }, mode: :compat)
      end

      @r.on 'cancel' do
        @r.patch do
          customer = find_customer!
          service  = SubscriptionService.new(customer: customer)
          sub      = service.cancel!(subscription_id: Integer(id))
          Oj.dump({ data: serialize(sub) }, mode: :compat)
        rescue ArgumentError => e
          @r.halt(422, Oj.dump({ error: e.message }, mode: :compat))
        end
      end

      @r.on 'charges' do
        @r.get do
          customer = find_customer!
          sub = Subscription.first(id: Integer(id), customer_id: customer.id)
          @r.halt(404, Oj.dump({ error: 'not_found' }, mode: :compat)) unless sub
          charges = Charge
                    .where(subscription_id: sub.id)
                    .order(Sequel.desc(:created_at))
                    .limit(20)
                    .all
          Oj.dump({
                    data: charges.map do |c|
                      { txid: c.txid, status: c.status, amount_cents: c.amount_cents, created_at: c.created_at.iso8601 }
                    end
                  }, mode: :compat)
        end
      end
    end
  end

  private

  def parse_body
    Oj.load(@r.body.read, mode: :compat) || {}
  end

  def find_customer!
    c = Customer.first(owner_type: 'user', owner_id: @auth.user_id)
    @r.halt(404, Oj.dump({ error: 'customer not found' }, mode: :compat)) unless c
    c
  end

  def serialize(sub)
    {
      id: sub.id,
      plan_name: sub.plan_name,
      status: sub.status,
      amount_cents: sub.amount_cents,
      interval: sub.interval,
      trial_ends_at: sub.trial_ends_at&.iso8601,
      current_period_end: sub.current_period_end&.iso8601,
      next_charge_at: sub.next_charge_at&.iso8601,
      cancelled_at: sub.cancelled_at&.iso8601,
      ends_at: sub.ends_at&.iso8601
    }
  end
end
