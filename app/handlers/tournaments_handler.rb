# frozen_string_literal: true

class TournamentsHandler
  def initialize(request, auth)
    @r    = request
    @auth = auth
  end

  def call
    @r.on ':tournament_id' do |tournament_id|
      @r.on 'distribute_prizes' do
        @r.post do
          @r.halt(403, Oj.dump({ error: 'admin_required' }, mode: :compat)) unless @auth.admin?

          body           = Oj.load(@r.body.read, mode: :compat) || {}
          placement_data = build_placement_data(body['placement_data'] || [])

          dist = PrizeDistributor.distribute!(
            tournament_id: Integer(tournament_id),
            total_collected_cents: Integer(body['total_collected_cents']),
            placement_data: placement_data
          )

          response.status = 202
          Oj.dump({ data: { distribution_id: dist.id, status: dist.status } }, mode: :compat)
        rescue ArgumentError => e
          @r.halt(422, Oj.dump({ error: e.message }, mode: :compat))
        end
      end

      @r.on 'financial_report' do
        @r.get do
          @r.halt(403, Oj.dump({ error: 'admin_required' }, mode: :compat)) unless @auth.admin?

          dist = PrizeDistribution.first(tournament_id: Integer(tournament_id))
          @r.halt(404, Oj.dump({ error: 'not_found' }, mode: :compat)) unless dist

          Oj.dump({ data: serialize_dist(dist) }, mode: :compat)
        end
      end
    end
  end

  private

  def build_placement_data(raw)
    raw.map { |p| { user_id: p['user_id'].to_i, placement: p['placement'].to_i } }
  end

  def serialize_dist(dist)
    {
      tournament_id: dist.tournament_id,
      total_collected_cents: dist.total_collected_cents,
      platform_fee_cents: dist.platform_fee_cents,
      prize_pool_cents: dist.prize_pool_cents,
      status: dist.status,
      distributed_at: dist.distributed_at&.iso8601,
      entries: dist.entries
    }
  end
end
