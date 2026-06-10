class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "Human Frequency <poole.reid@gmail.com>")
  layout "mailer"
end
