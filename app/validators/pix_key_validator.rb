# frozen_string_literal: true

class PixKeyValidator
  VALIDATORS = {
    'cpf' => ->(key) { key.match?(/\A\d{11}\z/) },
    'cnpj' => ->(key) { key.match?(/\A\d{14}\z/) },
    'email' => ->(key) { key.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/) && key.length <= 77 },
    'phone' => ->(key) { key.match?(/\A\+55\d{10,11}\z/) },
    'random' => ->(key) { key.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i) }
  }.freeze

  def self.valid?(pix_key_type, pix_key)
    validator = VALIDATORS[pix_key_type.to_s]
    return false unless validator

    validator.call(pix_key.to_s)
  end

  def self.valid_type?(pix_key_type)
    VALIDATORS.key?(pix_key_type.to_s)
  end
end
