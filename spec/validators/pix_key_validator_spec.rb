# frozen_string_literal: true

require 'spec_helper'

RSpec.describe PixKeyValidator do
  describe '.valid?' do
    context 'cpf' do
      it 'accepts 11 digits' do
        expect(described_class.valid?('cpf', '12345678901')).to be true
      end

      it 'rejects 10 digits' do
        expect(described_class.valid?('cpf', '1234567890')).to be false
      end

      it 'rejects with letters' do
        expect(described_class.valid?('cpf', '1234567890a')).to be false
      end
    end

    context 'cnpj' do
      it 'accepts 14 digits' do
        expect(described_class.valid?('cnpj', '12345678000195')).to be true
      end

      it 'rejects 13 digits' do
        expect(described_class.valid?('cnpj', '1234567800019')).to be false
      end
    end

    context 'email' do
      it 'accepts valid email' do
        expect(described_class.valid?('email', 'user@example.com')).to be true
      end

      it 'rejects without @' do
        expect(described_class.valid?('email', 'userexample.com')).to be false
      end

      it 'rejects email over 77 chars' do
        long = "#{'a' * 70}@b.com"
        expect(described_class.valid?('email', long)).to be false
      end
    end

    context 'phone' do
      it 'accepts +55 with 11 digits' do
        expect(described_class.valid?('phone', '+5511999998888')).to be true
      end

      it 'accepts +55 with 10 digits' do
        expect(described_class.valid?('phone', '+551199998888')).to be true
      end

      it 'rejects without +55 prefix' do
        expect(described_class.valid?('phone', '11999998888')).to be false
      end
    end

    context 'random (UUID v4)' do
      it 'accepts valid UUID v4' do
        expect(described_class.valid?('random', '550e8400-e29b-41d4-a716-446655440000')).to be false
        expect(described_class.valid?('random', '550e8400-e29b-4fd4-a716-446655440000')).to be true
      end

      it 'rejects plain string' do
        expect(described_class.valid?('random', 'not-a-uuid')).to be false
      end
    end
  end

  describe '.valid_type?' do
    it 'returns true for valid types' do
      %w[cpf cnpj email phone random].each do |type|
        expect(described_class.valid_type?(type)).to be true
      end
    end

    it 'returns false for unknown type' do
      expect(described_class.valid_type?('bank_account')).to be false
    end
  end
end
