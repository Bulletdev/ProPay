# frozen_string_literal: true

class Charge < Sequel::Model(:propay_charges)
  STATUSES        = %w[pending active paid expired cancelled refunded].freeze
  REFERENCE_TYPES = %w[subscription tournament_registration wallet_deposit].freeze

  many_to_one :customer,     class: :Customer,     key: :customer_id
  many_to_one :subscription, class: :Subscription, key: :subscription_id

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
