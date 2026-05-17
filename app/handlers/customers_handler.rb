# frozen_string_literal: true

class CustomersHandler
  def initialize(request, auth)
    @r    = request
    @auth = auth
  end

  def call
    @r.post do
      body = parse_body

      full_name = body['full_name'].to_s.strip
      email     = body['email'].to_s.strip

      @r.halt(422, Oj.dump({ error: 'full_name is required' }, mode: :compat)) if full_name.empty?
      @r.halt(422, Oj.dump({ error: 'email is required' }, mode: :compat)) if email.empty?

      existing = Customer.first(owner_type: 'user', owner_id: @auth.user_id)

      if existing
        @r.response.status = 200
        return Oj.dump({ data: serialize(existing) }, mode: :compat)
      end

      cpf_str = body['cpf'].to_s.strip
      customer = Customer.create(
        owner_type: 'user',
        owner_id: @auth.user_id,
        full_name: full_name,
        email: email,
        cpf: cpf_str.empty? ? nil : cpf_str
      )

      @r.response.status = 201
      Oj.dump({ data: serialize(customer) }, mode: :compat)
    end
  end

  private

  def parse_body
    Oj.load(@r.body.read, mode: :compat) || {}
  end

  def serialize(customer)
    {
      id: customer.id,
      owner_id: customer.owner_id,
      owner_type: customer.owner_type,
      full_name: customer.full_name,
      email: customer.email,
      created_at: customer.created_at.iso8601
    }
  end
end
