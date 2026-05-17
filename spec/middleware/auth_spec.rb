# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Middleware::Auth do
  let(:secret) { ENV.fetch('INTERNAL_JWT_SECRET') }

  def build_env(token)
    { 'HTTP_AUTHORIZATION' => token }
  end

  def encode_token(payload, signing_secret = secret)
    JWT.encode(payload, signing_secret, 'HS256')
  end

  describe '#valid?' do
    context 'with a valid JWT containing user_id' do
      let(:payload) { { 'user_id' => 7, 'role' => 'member', 'exp' => Time.now.to_i + 3600 } }
      let(:env)     { build_env("Bearer #{encode_token(payload)}") }

      subject { described_class.new(env) }

      it 'returns true' do
        expect(subject.valid?).to be true
      end
    end

    context 'without an Authorization header' do
      let(:env) { {} }

      subject { described_class.new(env) }

      it 'returns false' do
        expect(subject.valid?).to be false
      end
    end

    context 'with a malformed Authorization header (no Bearer prefix)' do
      let(:payload) { { 'user_id' => 7, 'exp' => Time.now.to_i + 3600 } }
      let(:env)     { build_env(encode_token(payload)) }

      subject { described_class.new(env) }

      it 'returns false' do
        expect(subject.valid?).to be false
      end
    end

    context 'with an expired token' do
      let(:payload) { { 'user_id' => 7, 'role' => 'member', 'exp' => Time.now.to_i - 1 } }
      let(:env)     { build_env("Bearer #{encode_token(payload)}") }

      subject { described_class.new(env) }

      it 'returns false' do
        expect(subject.valid?).to be false
      end
    end

    context 'with a token signed with the wrong secret' do
      let(:payload) { { 'user_id' => 7, 'role' => 'member', 'exp' => Time.now.to_i + 3600 } }
      let(:env)     { build_env("Bearer #{encode_token(payload, 'wrong_secret')}") }

      subject { described_class.new(env) }

      it 'returns false' do
        expect(subject.valid?).to be false
      end
    end

    context 'with a token that has no user_id claim' do
      let(:payload) { { 'role' => 'admin', 'exp' => Time.now.to_i + 3600 } }
      let(:env)     { build_env("Bearer #{encode_token(payload)}") }

      subject { described_class.new(env) }

      it 'returns false' do
        expect(subject.valid?).to be false
      end
    end

    context 'with a completely invalid token string' do
      let(:env) { build_env('Bearer not.a.jwt') }

      subject { described_class.new(env) }

      it 'returns false' do
        expect(subject.valid?).to be false
      end
    end
  end

  describe '#user_id' do
    let(:payload) { { 'user_id' => 42, 'role' => 'member', 'exp' => Time.now.to_i + 3600 } }
    let(:env)     { build_env("Bearer #{encode_token(payload)}") }

    subject { described_class.new(env) }

    it 'returns the user_id from the payload' do
      expect(subject.user_id).to eq('42')
    end

    context 'when the token is invalid' do
      subject { described_class.new({}) }

      it 'returns nil' do
        expect(subject.user_id).to be_nil
      end
    end
  end

  describe '#admin?' do
    context 'when role is admin' do
      let(:payload) { { 'user_id' => 1, 'role' => 'admin', 'exp' => Time.now.to_i + 3600 } }
      let(:env)     { build_env("Bearer #{encode_token(payload)}") }

      subject { described_class.new(env) }

      it 'returns true' do
        expect(subject.admin?).to be true
      end
    end

    context 'when role is member' do
      let(:payload) { { 'user_id' => 1, 'role' => 'member', 'exp' => Time.now.to_i + 3600 } }
      let(:env)     { build_env("Bearer #{encode_token(payload)}") }

      subject { described_class.new(env) }

      it 'returns false' do
        expect(subject.admin?).to be false
      end
    end

    context 'when role is coach' do
      let(:payload) { { 'user_id' => 1, 'role' => 'coach', 'exp' => Time.now.to_i + 3600 } }
      let(:env)     { build_env("Bearer #{encode_token(payload)}") }

      subject { described_class.new(env) }

      it 'returns false' do
        expect(subject.admin?).to be false
      end
    end

    context 'when there is no role claim' do
      let(:payload) { { 'user_id' => 1, 'exp' => Time.now.to_i + 3600 } }
      let(:env)     { build_env("Bearer #{encode_token(payload)}") }

      subject { described_class.new(env) }

      it 'returns false' do
        expect(subject.admin?).to be false
      end
    end
  end

  describe '#org_id' do
    let(:payload) { { 'user_id' => 1, 'org_id' => 55, 'role' => 'member', 'exp' => Time.now.to_i + 3600 } }
    let(:env)     { build_env("Bearer #{encode_token(payload)}") }

    subject { described_class.new(env) }

    it 'returns the org_id from the payload' do
      expect(subject.org_id).to eq(55)
    end
  end
end
