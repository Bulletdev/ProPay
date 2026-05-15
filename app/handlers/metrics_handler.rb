# frozen_string_literal: true

require 'prometheus/client/formats/text'

module MetricsHandler
  TRUSTED_PREFIXES = %w[127. 10. 192.168.].freeze

  def self.trusted_ip?(ip)
    ip = ip.to_s
    return true if TRUSTED_PREFIXES.any? { |prefix| ip.start_with?(prefix) }

    ip.start_with?('172.') && (16..31).cover?(ip.split('.')[1].to_i)
  end

  def self.call(request)
    request.get do
      forwarded_for = request.env['HTTP_X_FORWARDED_FOR']
      remote_ip = forwarded_for ? forwarded_for.split(',').first.strip : request.env['REMOTE_ADDR']

      request.halt(403, Oj.dump({ error: 'forbidden' }, mode: :compat)) unless MetricsHandler.trusted_ip?(remote_ip)

      MetricsService.refresh_subscription_gauges
      request.env['rack.response.headers'] ||= {}
      request.env['rack.response.headers']['Content-Type'] = Prometheus::Client::Formats::Text::CONTENT_TYPE
      Prometheus::Client::Formats::Text.marshal(MetricsService::REGISTRY)
    end
  end
end
