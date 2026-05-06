# frozen_string_literal: true

class BaseProvider
  def create_charge(amount_cents:, description:, txid:, expires_in:)
    raise NotImplementedError, "#{self.class}#create_charge not implemented"
  end

  def cancel_charge(txid:)
    raise NotImplementedError, "#{self.class}#cancel_charge not implemented"
  end

  def verify_webhook(headers:, raw_body:)
    raise NotImplementedError, "#{self.class}#verify_webhook not implemented"
  end

  private

  def secure_compare?(left, right)
    return false unless left.bytesize == right.bytesize

    l = left.unpack('C*')
    r = 0
    right.each_byte { |byte| r |= byte ^ l.shift }
    r.zero?
  end
end
