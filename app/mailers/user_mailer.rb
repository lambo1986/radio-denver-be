class UserMailer < ApplicationMailer
  def reset_password_email(user)
    @user = user
    frontend_url = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    @url = "#{frontend_url}/reset-password?token=#{ERB::Util.url_encode(@user.reset_password_token)}&email=#{ERB::Util.url_encode(@user.email)}"
    mail(to: @user.email, subject: 'Reset password instructions')
  end
end
