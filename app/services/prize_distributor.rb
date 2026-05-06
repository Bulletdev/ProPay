# frozen_string_literal: true

class PrizeDistributor
  PLATFORM_FEE_PERCENT = 0.20
  PLACEMENT_SHARES     = { 1 => 0.60, 2 => 0.20, 3 => 0.10 }.freeze

  def self.distribute!(tournament_id:, total_collected_cents:, placement_data:)
    existing = PrizeDistribution.first(tournament_id: tournament_id)
    raise ArgumentError, 'prizes already distributed' if existing&.status == 'distributed'

    platform_fee = (total_collected_cents * PLATFORM_FEE_PERCENT).floor
    prize_pool   = total_collected_cents - platform_fee
    entries      = build_entries(prize_pool, placement_data)

    DB.transaction do
      dist = existing || PrizeDistribution.create(
        tournament_id: tournament_id,
        total_collected_cents: total_collected_cents,
        platform_fee_cents: platform_fee,
        prize_pool_cents: prize_pool,
        status: 'pending',
        entries: Sequel.pg_json_wrap([])
      )

      PrizeDistributionJob.perform_async(dist.id, entries, "prize_#{tournament_id}")
      dist
    end
  end

  def self.build_entries(prize_pool, placement_data)
    placement_data.group_by { |p| p[:placement] }.flat_map do |placement, players|
      share             = PLACEMENT_SHARES.fetch(placement, 0)
      pool_for_position = (prize_pool * share).floor
      per_player        = players.empty? ? 0 : pool_for_position / players.size

      players.map { |p| { user_id: p[:user_id], placement: placement, amount_cents: per_player } }
    end
  end
end
