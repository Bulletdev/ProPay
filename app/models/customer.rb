# frozen_string_literal: true

class Customer < Sequel::Model(:propay_customers)
  one_to_many :charges,       class: :Charge,       key: :customer_id
  one_to_many :subscriptions, class: :Subscription, key: :customer_id
end
