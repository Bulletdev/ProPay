# frozen_string_literal: true

require 'dry-validation'

class ChargeValidator < Dry::Validation::Contract
  VALID_REFERENCE_TYPES = %w[subscription tournament_registration wallet_deposit].freeze

  params do
    required(:amount_cents).filled(:integer)
    required(:description).filled(:string)
    required(:reference_type).filled(:string)
    optional(:reference_id).maybe(:integer)
    optional(:expires_in_seconds).maybe(:integer)
  end

  rule(:amount_cents) do
    key.failure('must be greater than 0') if value <= 0
  end

  rule(:description) do
    key.failure('must be 140 characters or less') if value.length > 140
  end

  rule(:reference_type) do
    key.failure("must be one of: #{VALID_REFERENCE_TYPES.join(', ')}") unless VALID_REFERENCE_TYPES.include?(value)
  end

  rule(:expires_in_seconds) do
    next unless value

    key.failure('must be at least 300') if value < 300
    key.failure('must be at most 86400') if value > 86_400
  end
end
