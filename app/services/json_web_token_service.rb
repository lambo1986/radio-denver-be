class JsonWebTokenService
  def self.encode(payload)
    JWT.encode(payload, secret_key, 'HS256')
  end

  def self.decode(token)
    decoded = JWT.decode(token, secret_key, true, { algorithm: 'HS256' }).first
    symbolized_payload = symbolize_keys(decoded)
    symbolized_payload
  rescue JWT::ExpiredSignature
    nil
  end

  def self.secret_key
    ENV.fetch('JWT_SECRET_KEY', Rails.application.secret_key_base)
  end

  def self.symbolize_keys(value)
    case value
    when Array
      value.map { |v| symbolize_keys(v) }
    when Hash
      value.transform_keys { |k| k.to_sym }
    else
      value
    end
  end
end
