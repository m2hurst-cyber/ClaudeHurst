source "https://rubygems.org"

ruby "3.3.6"

gem "rails", ">= 7.2.3.1", "< 7.3"
gem "sprockets-rails"
gem "pg", "~> 1.5"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"

gem "bootsnap", require: false
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Auth & authorization
gem "devise", "~> 5.0"
gem "pundit", "~> 2.3"

# UI & forms
gem "simple_form", "~> 5.3"
gem "pagy", "~> 8.0"
gem "ransack", "~> 4.1"

# Business logic
gem "aasm", "~> 5.5"
gem "money-rails", "~> 1.15"

# Audit / soft-delete
gem "paper_trail", "~> 15.1"
gem "discard", "~> 1.3"

# PDF
gem "prawn", "~> 2.5"
gem "prawn-table", "~> 0.2"

# Jobs (Solid Queue — Postgres-backed)
gem "solid_queue", "~> 1.0"
gem "mission_control-jobs"

# File uploads (ActiveStorage needs image_processing for variants)
gem "image_processing", "~> 1.12"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ]
  gem "dotenv-rails", "~> 3.1"
  gem "factory_bot_rails", "~> 6.4"
end

group :development do
  gem "web-console"
  gem "letter_opener_web", "~> 3.0"
  gem "brakeman", require: false
  gem "bundler-audit", require: false
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end
