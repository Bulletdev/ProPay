# frozen_string_literal: true

require 'dotenv/load' if File.exist?('.env')

PROPAY_VERSION  = '1.0.0'
SUPPORTED_PLANS = %w[pro_monthly pro_annual enterprise].freeze
PIX_KEY_TYPES   = %w[cpf cnpj email phone random].freeze
VALID_PROVIDERS = %w[openpix efi].freeze

require_relative 'database'
require_relative 'redis'

Dir[File.join(__dir__, '..', 'app', 'models',    '*.rb')].each { |f| require f }
Dir[File.join(__dir__, '..', 'app', 'providers', '*.rb')].each { |f| require f }
Dir[File.join(__dir__, '..', 'app', 'services',  '*.rb')].each { |f| require f }
Dir[File.join(__dir__, '..', 'app', 'jobs',      '*.rb')].each { |f| require f }
