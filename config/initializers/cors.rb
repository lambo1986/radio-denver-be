configured_origins = ENV.fetch('FRONTEND_ORIGINS', '').split(',').map(&:strip).reject(&:blank?)

if configured_origins.empty?
  if Rails.env.production?
    raise 'FRONTEND_ORIGINS must list the allowed production frontend origin(s).'
  end

  configured_origins = ['http://localhost:3000']
end

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*configured_origins)

    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: true
  end
end
