# frozen_string_literal: true

require 'prometheus/client/formats/text'

module MetricsHandler
  def self.call(request)
    request.get do
      MetricsService.refresh_subscription_gauges
      request.env['rack.response.headers'] ||= {}
      request.env['rack.response.headers']['Content-Type'] = Prometheus::Client::Formats::Text::CONTENT_TYPE
      Prometheus::Client::Formats::Text.marshal(MetricsService::REGISTRY)
    end
  end
end
