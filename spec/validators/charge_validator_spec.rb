# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ChargeValidator do
  subject(:validator) { described_class.new }

  let(:valid_params) do
    {
      amount_cents: 1000,
      description: 'Copa ArenaBR inscricao',
      reference_type: 'tournament_registration',
      reference_id: 42,
      expires_in_seconds: 3600
    }
  end

  it 'passes with valid params' do
    expect(validator.call(valid_params)).to be_success
  end

  it 'fails when amount_cents is zero' do
    result = validator.call(valid_params.merge(amount_cents: 0))
    expect(result).to be_failure
    expect(result.errors[:amount_cents]).to include('must be greater than 0')
  end

  it 'fails when amount_cents is negative' do
    result = validator.call(valid_params.merge(amount_cents: -100))
    expect(result).to be_failure
  end

  it 'fails when description is missing' do
    result = validator.call(valid_params.except(:description))
    expect(result).to be_failure
  end

  it 'fails when description exceeds 140 chars' do
    result = validator.call(valid_params.merge(description: 'a' * 141))
    expect(result).to be_failure
    expect(result.errors[:description]).to include('must be 140 characters or less')
  end

  it 'fails with invalid reference_type' do
    result = validator.call(valid_params.merge(reference_type: 'invalid'))
    expect(result).to be_failure
  end

  it 'fails when expires_in_seconds is below 300' do
    result = validator.call(valid_params.merge(expires_in_seconds: 299))
    expect(result).to be_failure
    expect(result.errors[:expires_in_seconds]).to include('must be at least 300')
  end

  it 'fails when expires_in_seconds exceeds 86400' do
    result = validator.call(valid_params.merge(expires_in_seconds: 86_401))
    expect(result).to be_failure
    expect(result.errors[:expires_in_seconds]).to include('must be at most 86400')
  end

  it 'passes without optional fields' do
    result = validator.call(valid_params.except(:reference_id, :expires_in_seconds))
    expect(result).to be_success
  end
end
