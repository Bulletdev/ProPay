# frozen_string_literal: true

require 'dry-validation'

class SubscriptionValidator < Dry::Validation::Contract
  VALID_PLANS = %w[pro_monthly pro_annual enterprise].freeze

  params do
    required(:plan_name).filled(:string)
    optional(:trial_days).maybe(:integer)
  end

  rule(:plan_name) do
    key.failure("must be one of: #{VALID_PLANS.join(', ')}") unless VALID_PLANS.include?(value)
  end

  rule(:trial_days) do
    next unless value

    key.failure('must be between 0 and 90') unless value.between?(0, 90)
  end
end
