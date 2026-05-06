# frozen_string_literal: true

class Subscription < Sequel::Model(:propay_subscriptions)
  STATUSES = %w[trialing active past_due cancelled].freeze

  many_to_one :customer, class: :Customer, key: :customer_id
  one_to_many :charges,  class: :Charge,   key: :subscription_id

  def before_create
    self.created_at ||= Time.now.utc
    self.updated_at ||= Time.now.utc
    super
  end

  def before_update
    self.updated_at = Time.now.utc
    super
  end
end
