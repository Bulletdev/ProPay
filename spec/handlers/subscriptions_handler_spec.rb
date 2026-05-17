# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Subscriptions API', type: :request do
  let(:user_id)  { '1' }
  let(:customer) { create_customer(owner_id: user_id) }

  let(:subscription) do
    SubscriptionService.new(customer: customer).create!(plan_name: 'pro_monthly', trial_days: 14)
  end

  describe 'POST /v1/subscriptions' do
    let(:valid_body) do
      Oj.dump({ 'plan_name' => 'pro_monthly', 'trial_days' => 14 }, mode: :compat)
    end

    context 'without JWT' do
      it 'returns 401' do
        post '/v1/subscriptions', valid_body, { 'CONTENT_TYPE' => 'application/json' }
        expect(last_response.status).to eq(401)
      end
    end

    context 'when customer does not exist' do
      it 'returns 404' do
        post '/v1/subscriptions',
             valid_body,
             auth_header(user_id: '999').merge('CONTENT_TYPE' => 'application/json')

        expect(last_response.status).to eq(404)
        expect(json_body['error']).to eq('customer not found')
      end
    end

    context 'with a valid customer and valid plan' do
      before { customer }

      it 'returns 201' do
        post '/v1/subscriptions',
             valid_body,
             auth_header(user_id: user_id).merge('CONTENT_TYPE' => 'application/json')

        expect(last_response.status).to eq(201)
      end

      it 'creates the subscription with status trialing' do
        post '/v1/subscriptions',
             valid_body,
             auth_header(user_id: user_id).merge('CONTENT_TYPE' => 'application/json')

        data = json_body['data']
        expect(data['plan_name']).to eq('pro_monthly')
        expect(data['status']).to eq('trialing')
        expect(data['amount_cents']).to eq(4900)
        expect(data['interval']).to eq('month')
        expect(data['trial_ends_at']).to be_present
        expect(data['id']).to be_present
      end
    end

    context 'with an invalid plan_name' do
      before { customer }

      it 'returns 422' do
        body = Oj.dump({ 'plan_name' => 'invalid_plan', 'trial_days' => 14 }, mode: :compat)

        post '/v1/subscriptions',
             body,
             auth_header(user_id: user_id).merge('CONTENT_TYPE' => 'application/json')

        expect(last_response.status).to eq(422)
        expect(json_body['error']).to match(/invalid plan/)
      end
    end

    context 'when the customer already has an active subscription' do
      before do
        customer
        subscription
      end

      it 'returns the existing subscription without creating a duplicate' do
        existing_id = subscription.id

        post '/v1/subscriptions',
             valid_body,
             auth_header(user_id: user_id).merge('CONTENT_TYPE' => 'application/json')

        expect(last_response.status).to eq(201)
        expect(json_body['data']['id']).to eq(existing_id)
        expect(Subscription.where(customer_id: customer.id).count).to eq(1)
      end
    end
  end

  describe 'GET /v1/subscriptions/:id' do
    before do
      customer
      subscription
    end

    context 'without JWT' do
      it 'returns 401' do
        get "/v1/subscriptions/#{subscription.id}"
        expect(last_response.status).to eq(401)
      end
    end

    context 'with valid JWT and existing subscription' do
      it 'returns 200' do
        get "/v1/subscriptions/#{subscription.id}", {}, auth_header(user_id: user_id)
        expect(last_response.status).to eq(200)
      end

      it 'returns the subscription payload' do
        get "/v1/subscriptions/#{subscription.id}", {}, auth_header(user_id: user_id)

        data = json_body['data']
        expect(data['id']).to eq(subscription.id)
        expect(data['plan_name']).to eq('pro_monthly')
        expect(data['status']).to eq('trialing')
      end
    end

    context 'with a non-existent id' do
      it 'returns 404' do
        get '/v1/subscriptions/999999', {}, auth_header(user_id: user_id)
        expect(last_response.status).to eq(404)
        expect(json_body['error']).to eq('not_found')
      end
    end
  end

  describe 'GET /v1/subscriptions/by_owner/:owner_id' do
    context 'when the owner has a subscription' do
      before do
        customer
        subscription
      end

      it 'returns the subscription' do
        get "/v1/subscriptions/by_owner/#{user_id}", {}, auth_header(user_id: user_id)

        expect(last_response.status).to eq(200)
        data = json_body['data']
        expect(data['id']).to eq(subscription.id)
        expect(data['plan_name']).to eq('pro_monthly')
      end
    end

    context 'when the owner has no subscription' do
      before { customer }

      it 'returns data as nil' do
        get "/v1/subscriptions/by_owner/#{user_id}", {}, auth_header(user_id: user_id)

        expect(last_response.status).to eq(200)
        expect(json_body['data']).to be_nil
      end
    end

    context 'when the owner does not exist' do
      it 'returns data as nil' do
        get '/v1/subscriptions/by_owner/99999', {}, auth_header(user_id: user_id)

        expect(last_response.status).to eq(200)
        expect(json_body['data']).to be_nil
      end
    end
  end

  describe 'PATCH /v1/subscriptions/:id/cancel' do
    before do
      customer
      subscription
      allow(TierSyncJob).to receive(:perform_async)
    end

    context 'without JWT' do
      it 'returns 401' do
        patch "/v1/subscriptions/#{subscription.id}/cancel"
        expect(last_response.status).to eq(401)
      end
    end

    context 'with a valid active subscription' do
      it 'cancels the subscription and returns 200' do
        patch "/v1/subscriptions/#{subscription.id}/cancel",
              {},
              auth_header(user_id: user_id)

        expect(last_response.status).to eq(200)
        data = json_body['data']
        expect(data['status']).to eq('cancelled')
        expect(data['cancelled_at']).to be_present
        expect(data['ends_at']).to be_present
      end
    end

    context 'when subscription is already cancelled' do
      before do
        SubscriptionService.new(customer: customer).cancel!(subscription_id: subscription.id)
      end

      it 'returns 422' do
        patch "/v1/subscriptions/#{subscription.id}/cancel",
              {},
              auth_header(user_id: user_id)

        expect(last_response.status).to eq(422)
        expect(json_body['error']).to eq('already cancelled')
      end
    end
  end
end
