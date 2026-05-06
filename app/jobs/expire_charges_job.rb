# frozen_string_literal: true

require 'sidekiq'

class ExpireChargesJob
  include Sidekiq::Job

  sidekiq_options queue: 'low', retry: 3

  def perform
    count = Charge.where(status: 'active').where { expires_at < Time.now.utc }.update(status: 'expired')
    Sidekiq.logger.info("[ExpireChargesJob] expired=#{count}")
  end
end
