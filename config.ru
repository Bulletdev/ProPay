# frozen_string_literal: true

require 'dotenv/load' if File.exist?('.env')
require 'oj'
require 'iodine'
require 'rack/attack'
require 'rack/cors'

Iodine.threads = Integer(ENV.fetch('IODINE_THREADS', 4))
Iodine.workers = Integer(ENV.fetch('IODINE_WORKERS', 1))

PROPAY_VERSION  = '1.0.0'
SUPPORTED_PLANS = %w[pro_monthly pro_annual enterprise].freeze
PIX_KEY_TYPES   = %w[cpf cnpj email phone random].freeze
VALID_PROVIDERS = %w[openpix efi].freeze

require_relative 'config/database'
require_relative 'config/redis'

# Load order: models -> services -> jobs -> handlers
Dir[File.join(__dir__, 'app', 'models', '*.rb')].each      { |f| require f }
Dir[File.join(__dir__, 'app', 'middleware', '*.rb')].each  { |f| require f }
Dir[File.join(__dir__, 'app', 'providers', '*.rb')].each   { |f| require f }
Dir[File.join(__dir__, 'app', 'services', '*.rb')].each    { |f| require f }
Dir[File.join(__dir__, 'app', 'jobs', '*.rb')].each        { |f| require f }
Dir[File.join(__dir__, 'app', 'handlers', '*.rb')].each    { |f| require f }

Rack::Attack.throttle('propay/ip', limit: 30, period: 60, &:ip)
Rack::Attack.throttle('propay/user', limit: 10, period: 60) do |req|
  req.env['propay.user_id']
end

GC.compact

require_relative 'app/propay_app'

CORS_ORIGINS = "#{ENV.fetch('CORS_ORIGINS', '')},https://arena-br.vercel.app,https://prostaff.gg"
               .split(',').map(&:strip).reject(&:empty?).freeze

app = Rack::Cors.new(ProPayApp.freeze.app) do
  allow do
    origins(*CORS_ORIGINS)
    resource '/v1/*',
             headers: :any,
             methods: %i[get post patch delete options],
             expose: ['X-Request-Id'],
             max_age: 600
  end
end

run app
