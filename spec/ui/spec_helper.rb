# frozen_string_literal: true

require 'rspec'
require 'fileutils'
require 'dotenv'

# Load environment variables from .env file (if present)
Dotenv.load

# Load support files
Dir[File.join(__dir__, 'support', '*.rb')].each { |f| require f }

# Load shared contexts
Dir[File.join(__dir__, 'support', 'shared_contexts', '*.rb')].each { |f| require f }

# Include custom matchers
RSpec.configure do |config|
  config.include UITest::Matchers

  # Use documentation format for better output
  config.formatter = :documentation

  # Run tests in random order to surface dependencies
  config.order = :defined # Use defined order for UI tests (they may have dependencies)

  # Show full backtrace on failure
  config.full_backtrace = false

  # Filter stack traces to remove gem noise
  config.filter_gems_from_backtrace 'rspec-core', 'rspec-expectations', 'rspec-mocks', 'rspec-support'

  # Retry configuration for flaky UI tests
  config.around(:each, :retry) do |example|
    example.run_with_retry(retry: 2, retry_wait: 1)
  end

  # Hooks for visual tests
  config.before(:each, :visual) do
    UITest::Config.ensure_directories!
  end

  # Global setup - ensure clean state
  config.before(:suite) do
    puts ''
    puts '=' * 60
    puts 'Yattee UI Tests'
    puts '=' * 60
    puts "Device: #{UITest::Config.device}"
    puts "Generate baseline: #{UITest::Config.generate_baseline?}"
    puts "Skip build: #{UITest::Config.skip_build?}"
    puts "Keep app data: #{UITest::Config.keep_app_data?}"
    puts '=' * 60
    puts ''
  end

  # Global teardown
  config.after(:suite) do
    puts ''
    puts '=' * 60
    puts 'UI Tests Complete'
    puts '=' * 60
  end
end

# RSpec retry gem configuration (if available)
begin
  require 'rspec/retry'
  RSpec.configure do |config|
    config.verbose_retry = true
    config.display_try_failure_messages = true
  end
rescue LoadError
  # rspec-retry not installed, skip
end
