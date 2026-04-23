# frozen_string_literal: true

# Shared context that ensures a Yattee Server instance is configured
# before running tests that depend on it.
#
# Usage in specs:
#   RSpec.describe 'Feature requiring Yattee Server', :smoke do
#     include_context 'with Yattee Server instance'
#
#     it 'does something with Yattee Server' do
#       # Instance is guaranteed to exist
#     end
#   end
#
RSpec.shared_context 'with Yattee Server instance' do
  before(:all) do
    @instance_setup ||= UITest::InstanceSetup.new(@axe)
    @instance_setup.ensure_yattee_server(UITest::Config.yattee_server_url)
  end
end
