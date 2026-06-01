class UserSerializer
  include JSONAPI::Serializer

  set_type :user
  attributes :first_name,
             :last_name,
             :email,
             :host_name,
             :description,
             :profile_image,
             :phone_number,
             :role
end
