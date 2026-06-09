class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "Alpine Groove Guide <radio@alpinegrooveguide.com>")
  layout "mailer"
end
