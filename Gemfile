# frozen_string_literal: true

source "https://rubygems.org"

# Fastlane for build automation and distribution
gem 'fastlane', '~> 2.225'

# Load environment variables from .env files
# Note: fastlane requires dotenv < 3.0, so we use 2.x
gem 'dotenv', '~> 2.8'

group :test do
  # RSpec for UI testing framework
  gem 'rspec', '~> 3.13'
  # Retry flaky UI tests automatically
  gem 'rspec-retry', '~> 0.6'
  # Code linting
  gem 'rubocop', '~> 1.69', require: false
  gem 'rubocop-rspec', '~> 3.3', require: false
end
