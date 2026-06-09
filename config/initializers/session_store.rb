Rails.application.config.session_store(
  :cookie_store,
  key: ENV.fetch("SESSION_COOKIE_KEY", "_melody_mixer_session"),
  secure: Rails.env.production?,
  httponly: true,
  same_site: Rails.env.production? ? :none : :lax
)
