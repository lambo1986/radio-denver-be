class UserSerializer
  include JSONAPI::Serializer

  set_type :user
  attributes :first_name,
             :last_name,
             :email,
             :host_name,
             :description,
             :phone_number,
             :role,
             :account_status

  attribute :profile_image do |user|
    user.profile_image_url
  end
end
