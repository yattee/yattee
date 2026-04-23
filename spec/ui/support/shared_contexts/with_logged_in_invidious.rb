# frozen_string_literal: true

# Shared context that ensures an Invidious instance is configured AND logged in
# before running tests that depend on it.
#
# Requires environment variables:
#   INVIDIOUS_EMAIL - Invidious account email/username
#   INVIDIOUS_PASSWORD - Invidious account password
#
# Usage in specs:
#   RSpec.describe 'Feature requiring logged-in Invidious', :smoke do
#     include_context 'with logged-in Invidious'
#
#     it 'does something with Invidious account' do
#       # Instance is guaranteed to exist and be logged in
#     end
#   end
#
RSpec.shared_context 'with logged-in Invidious' do
  before(:all) do
    skip 'Invidious credentials not configured' unless UITest::Config.invidious_credentials?

    @instance_setup ||= UITest::InstanceSetup.new(@axe)
    @instance_setup.ensure_invidious(UITest::Config.invidious_url)
    @instance_setup.ensure_invidious_logged_in(UITest::Config.invidious_host)
  end
end
