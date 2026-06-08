# spec/requests/api/v1/password_reset_spec.rb

RSpec.describe 'Password Resets', type: :request do
  describe 'POST /api/v1/password_resets' do
    let!(:user) { create(:user) }

    context 'when the email is valid' do
      it 'creates a new password reset token and sends an email' do
        expect {
          post '/api/v1/password_resets', params: { email: user.email }
        }.to change { ActionMailer::Base.deliveries.count }.by(1)

        json = JSON.parse(response.body)

        expect(response).to have_http_status(:ok)
        expect(json['message']).to include('password reset instructions')
        expect(user.reload.reset_password_token).not_to be_nil
        expect(ActionMailer::Base.deliveries.last.body.encoded).to include('/reset-password?token=')
        expect(ActionMailer::Base.deliveries.last.body.encoded).to include(ERB::Util.url_encode(user.email))
      end
    end

    context 'when the email is not valid' do
      it 'returns the same response without revealing account existence' do
        post '/api/v1/password_resets', params: { email: 'nonexistent@example.com' }

        json = JSON.parse(response.body)

        expect(response).to have_http_status(:ok)
        expect(json['message']).to include('password reset instructions')
        expect(ActionMailer::Base.deliveries).to be_empty
      end
    end

    it 'matches email addresses case-insensitively' do
      post '/api/v1/password_resets', params: { email: "  #{user.email.upcase} " }

      expect(response).to have_http_status(:ok)
      expect(user.reload.reset_password_token).to be_present
    end

    it 'rate limits repeated requests for one email address' do
      3.times { post '/api/v1/password_resets', params: { email: user.email } }

      post '/api/v1/password_resets', params: { email: user.email.upcase }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers['Retry-After']).to be_present
    end
  end

  describe 'PATCH /api/v1/password_resets/:token' do
    let!(:user) { create(:user) }
    before do
      user.generate_password_token!
    end

    context 'when the token is valid' do
      it 'successfully resets the user password' do
        patch update_with_token_api_v1_password_resets_path(user.reset_password_token),
              params: { email: user.email, password: 'newpassword123', password_confirmation: 'newpassword123' }
        user.reload

        expect(user.authenticate('newpassword123')).to be_truthy
        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)

        expect(json['message']).to eq('Password has been reset successfully.')
      end
    end

    context 'when the token is invalid or expired' do
      it 'returns an error message' do
        patch update_with_token_api_v1_password_resets_path('invalid_token'),
              params: { email: user.email, password: 'newpassword123', password_confirmation: 'newpassword123' }

        expect(response).to have_http_status(:not_found)

        json = JSON.parse(response.body)

        expect(json['error']).to eq('Password token is invalid or has expired')
      end
    end

    context 'when passwords do not match' do
      it 'does not reset the password' do
        patch update_with_token_api_v1_password_resets_path(user.reset_password_token),
              params: { email: user.email, password: 'newpassword123', password_confirmation: 'wrongconfirmation' }

        expect(response).to have_http_status(:unprocessable_entity)

        json = JSON.parse(response.body)

        expect(json['errors']).to include("Password confirmation doesn't match Password")
      end
    end
  end
end
