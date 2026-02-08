# frozen_string_literal: true

# Shared context that ensures a Piped instance is configured AND logged in
# before running tests that depend on it.
#
# Requires environment variables:
#   PIPED_USERNAME - Piped account username
#   PIPED_PASSWORD - Piped account password
#
# Usage in specs:
#   RSpec.describe 'Feature requiring logged-in Piped', :smoke do
#     include_context 'with logged-in Piped'
#
#     it 'does something with Piped account' do
#       # Instance is guaranteed to exist and be logged in
#     end
#   end
#
RSpec.shared_context 'with logged-in Piped' do
  before(:all) do
    skip 'Piped credentials not configured' unless UITest::Config.piped_credentials?

    @instance_setup ||= UITest::InstanceSetup.new(@axe)
    @instance_setup.ensure_piped(UITest::Config.piped_url)
    @instance_setup.ensure_piped_logged_in(UITest::Config.piped_host)
  end
end
