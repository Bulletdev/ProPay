# frozen_string_literal: true

require 'jwt'

module Middleware
  class Auth
    ALGORITHM = 'HS256'

    attr_reader :user_id, :org_id, :role

    def initialize(env)
      @payload = decode_token(env)
      @user_id = @payload&.dig('user_id')&.to_s
      @org_id  = @payload&.dig('org_id')
      @role    = @payload&.dig('role')
    end

    def valid?
      !@payload.nil? && !@user_id.nil?
    end

    def admin?
      @role == 'admin'
    end

    def service?
      @role == 'service'
    end

    private

    def decode_token(env)
      header = env['HTTP_AUTHORIZATION']
      return nil unless header&.start_with?('Bearer ')

      token   = header.split(' ', 2).last
      decoded = JWT.decode(token, ENV.fetch('INTERNAL_JWT_SECRET'), true, algorithm: ALGORITHM)
      decoded.first
    rescue JWT::DecodeError
      nil
    end
  end
end
