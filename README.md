# README

This is a project being brewed by myself and Reid Poole that will serve as a sort of radio station for users to create their own radio show, complete with music and voice recording. 

## Setup

1. Clone repo down to your machine.

2. Install Rails 7.1.3.3 and Ruby version 3.1.4
```
rbenv install 3.1.4
rbenv local 3.1.4
gem install rails -v 7.1.3.2
```

3. Install Bundler
```
gem install bundler
bundle install
```

4. Setup Databases
```
rails db:create
rails db:migrate
```

5. Run Tests
```
bundle exec rspec
```

6. Run Server
```
rails server
```

## Production Configuration

Set the allowed frontend origin before booting Rails in production:

```env
FRONTEND_ORIGINS=https://app.example.com
```

Multiple trusted frontends can be provided as a comma-separated list. Do not use `*` because the API uses credentialed sessions.

Login and password-reset throttles currently use an in-process memory store. This is appropriate for the single-process MVP. Configure a shared Redis-backed limiter before running multiple Rails instances.

* Nathan Lambertson
