# frozen_string_literal: true

require 'sidekiq'

class PrizeDistributionJob
  include Sidekiq::Job

  sidekiq_options queue: 'default', retry: 5

  def perform(distribution_id, entries, idempotency_prefix)
    dist = PrizeDistribution[distribution_id]
    return unless dist&.status == 'pending'

    DB.transaction do
      credit_entries(entries, idempotency_prefix)
      dist.update(
        status: 'distributed',
        distributed_at: Time.now.utc,
        entries: Sequel.pg_json_wrap(entries)
      )
    end
  end

  private

  def credit_entries(entries, idempotency_prefix)
    entries.each do |entry|
      uid    = (entry['user_id']      || entry[:user_id]).to_i
      amount = (entry['amount_cents'] || entry[:amount_cents]).to_i
      place  = entry['placement']     || entry[:placement]

      WalletService.credit!(
        user_id: uid,
        amount_cents: amount,
        type: 'prize_credit',
        description: "Tournament prize placement #{place}",
        idempotency_key: "#{idempotency_prefix}_user#{uid}"
      )
    end
  end
end
