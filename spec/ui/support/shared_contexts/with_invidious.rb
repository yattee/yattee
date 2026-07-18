# frozen_string_literal: true

# Shared context that ensures an Invidious instance is configured
# before running tests that depend on it.
#
# Usage in specs:
#   RSpec.describe 'Feature requiring Invidious', :smoke do
#     include_context 'with Invidious instance'
#
#     it 'does something with Invidious' do
#       # Instance is guaranteed to exist
#     end
#   end
#
RSpec.shared_context 'with Invidious instance' do
  before(:all) do
    @instance_setup ||= UITest::InstanceSetup.new(@axe)
    @instance_setup.ensure_invidious(UITest::Config.invidious_url)
  end
end
