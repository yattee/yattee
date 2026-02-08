# frozen_string_literal: true

# Shared context that ensures a Piped instance is configured
# before running tests that depend on it.
#
# Usage in specs:
#   RSpec.describe 'Feature requiring Piped', :smoke do
#     include_context 'with Piped instance'
#
#     it 'does something with Piped' do
#       # Instance is guaranteed to exist
#     end
#   end
#
RSpec.shared_context 'with Piped instance' do
  before(:all) do
    @instance_setup ||= UITest::InstanceSetup.new(@axe)
    @instance_setup.ensure_piped(UITest::Config.piped_url)
  end
end
