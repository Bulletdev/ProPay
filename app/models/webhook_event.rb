# frozen_string_literal: true

class WebhookEvent < Sequel::Model(:propay_webhook_events)
  STATUSES = %w[pending processed failed].freeze

  def before_create
    self.created_at ||= Time.now.utc
    super
  end
end
