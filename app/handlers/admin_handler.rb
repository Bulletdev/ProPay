# frozen_string_literal: true

class AdminHandler
  def initialize(request, auth)
    @r    = request
    @auth = auth
  end

  def call
    @r.halt(403, Oj.dump({ error: 'admin_required' }, mode: :compat)) unless @auth.admin?

    @r.on 'dashboard' do
      @r.get { Oj.dump({ data: dashboard_data }, mode: :compat) }
    end

    @r.on 'subscriptions' do
      @r.get do
        page     = [(@r.params['page'] || 1).to_i, 1].max
        per_page = 50
        offset   = (page - 1) * per_page
        status   = @r.params['status']

        scope = status ? Subscription.where(status: status) : Subscription.all
        subs  = scope.order(Sequel.desc(:created_at)).limit(per_page).offset(offset).all
        total = scope.count

        Oj.dump({
                  data: subs.map { |s| serialize_subscription(s) },
                  meta: { total: total, page: page, per_page: per_page }
                }, mode: :compat)
      end
    end

    @r.on 'charges' do
      @r.get do
        page     = [(@r.params['page'] || 1).to_i, 1].max
        per_page = 50
        offset   = (page - 1) * per_page
        status   = @r.params['status']

        scope   = status ? Charge.where(status: status) : Charge.all
        charges = scope.order(Sequel.desc(:created_at)).limit(per_page).offset(offset).all
        total   = scope.count

        Oj.dump({
                  data: charges.map { |c| serialize_charge(c) },
                  meta: { total: total, page: page, per_page: per_page }
                }, mode: :compat)
      end
    end

    @r.on 'wallets' do
      @r.get do
        top_wallets   = Wallet.order(Sequel.desc(:balance_cents)).limit(20).all
        total_balance = Wallet.sum(:balance_cents).to_i
        Oj.dump({
                  data: {
                    total_balance_cents: total_balance,
                    top_wallets: top_wallets.map { |w| { user_id: w.user_id, balance_cents: w.balance_cents } }
                  }
                }, mode: :compat)
      end
    end
  end

  private

  def dashboard_data
    now         = Time.now.utc
    today_start = Time.utc(now.year, now.month, now.day)

    {
      charges: charges_summary(today_start),
      subscriptions: subscriptions_summary,
      wallets: wallets_summary,
      payouts: payouts_summary
    }
  end

  def charges_summary(today_start)
    {
      total: Charge.count,
      paid_today: Charge.where(status: 'paid').where { paid_at >= today_start }.count,
      pending: Charge.where(status: %w[pending active]).count,
      revenue_today_cents: Charge.where(status: 'paid').where { paid_at >= today_start }.sum(:amount_cents).to_i
    }
  end

  def subscriptions_summary
    {
      active: Subscription.where(status: 'active').count,
      trialing: Subscription.where(status: 'trialing').count,
      past_due: Subscription.where(status: 'past_due').count,
      cancelled: Subscription.where(status: 'cancelled').count
    }
  end

  def wallets_summary
    {
      total: Wallet.count,
      total_balance_cents: Wallet.sum(:balance_cents).to_i
    }
  end

  def payouts_summary
    {
      pending: Payout.where(status: 'pending').count,
      processing: Payout.where(status: 'processing').count,
      failed: Payout.where(status: 'failed').count
    }
  end

  def serialize_subscription(sub)
    {
      id: sub.id,
      customer_id: sub.customer_id,
      plan_name: sub.plan_name,
      status: sub.status,
      amount_cents: sub.amount_cents,
      created_at: sub.created_at.iso8601
    }
  end

  def serialize_charge(charge)
    {
      id: charge.id,
      txid: charge.txid,
      customer_id: charge.customer_id,
      amount_cents: charge.amount_cents,
      status: charge.status,
      reference_type: charge.reference_type,
      paid_at: charge.paid_at&.iso8601,
      created_at: charge.created_at.iso8601
    }
  end
end
