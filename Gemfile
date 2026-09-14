source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
# 8.1.3.1 is the patch release fixing CVE-2026-66066 (activestorage).
gem "rails", "8.1.3.1"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"

# RSS/Atom feed parsing [https://github.com/feedjira/feedjira]
gem "feedjira"

# Rails 8.1 is incompatible with json 3.x's JSON.parse signature
gem "json", "~> 2.21"

# pt-BR translations for ActiveRecord errors, date/time formats and friends
# [https://github.com/svenfuchs/rails-i18n]
gem "rails-i18n", "~> 8.0"

# Database-backed Active Job queue with recurring tasks [https://github.com/rails/solid_queue]
gem "solid_queue"

# Dashboard for inspecting queues and retrying/discarding jobs
# [https://github.com/rails/mission_control-jobs]
gem "mission_control-jobs"

# SMTP delivery for Action Mailer [https://github.com/ruby/net-smtp]
gem "net-smtp"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Loads .env into ENV for local runs. Rails does not read .env by itself — in
  # production the file is consumed by docker compose (`env_file: .env`).
  # Development only, so the test suite never picks up a developer's real
  # SMTP credentials or APP_HOST.
  gem "dotenv-rails"

  # Opens sent email in the browser instead of delivering it, so the weekly
  # clipping can be reviewed locally without emailing real subscribers.
  gem "letter_opener"
end

gem "tailwindcss-rails", "~> 4.6"
