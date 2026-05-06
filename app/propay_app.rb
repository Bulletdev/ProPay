# frozen_string_literal: true

require 'roda'

class ProPayApp < Roda
  plugin :json
  plugin :json_parser
  plugin :halt
  plugin :status_handler
  plugin :request_headers

  status_handler(404) { Oj.dump({ error: 'not_found' }, mode: :compat) }
  status_handler(422) { Oj.dump({ error: 'unprocessable_entity' }, mode: :compat) }
  status_handler(500) { Oj.dump({ error: 'internal_server_error' }, mode: :compat) }

  route do |r|
    response['Content-Type'] = 'application/json'

    r.on 'metrics' do
      MetricsHandler.call(r)
    end

    r.get 'health' do
      Oj.dump(HealthHandler.status, mode: :compat)
    end

    r.on 'v1' do
      r.on 'health' do
        r.get { Oj.dump(HealthHandler.status, mode: :compat) }
      end

      r.on 'ready' do
        r.get do
          result = HealthHandler.ready
          response.status = result[:ok] ? 200 : 503
          Oj.dump(result, mode: :compat)
        end
      end

      r.on 'webhooks' do
        WebhooksHandler.new(r).call
      end

      auth = Middleware::Auth.new(r.env)
      r.halt(401, Oj.dump({ error: 'unauthorized' }, mode: :compat)) unless auth.valid?

      r.env['propay.user_id'] = auth.user_id.to_s

      r.on('charges')       { ChargesHandler.new(r, auth).call }
      r.on('subscriptions') { SubscriptionsHandler.new(r, auth).call }
      r.on('wallet')        { WalletHandler.new(r, auth).call }
      r.on('tournaments')   { TournamentsHandler.new(r, auth).call }
      r.on('admin')         { AdminHandler.new(r, auth).call }
    end
  end
end
