# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'Invidious Instance', :smoke do
  before(:all) do
    # Boot simulator
    @udid = UITest::Simulator.boot(UITest::Config.device)

    # Build app (unless skipped)
    UITest::App.build(
      device: UITest::Config.device,
      skip: UITest::Config.skip_build?
    )

    # Install and launch
    UITest::App.install(udid: @udid)
    UITest::App.launch(udid: @udid)

    # Wait for app to stabilize
    sleep UITest::Config.app_launch_wait

    # Initialize AXe and InstanceSetup helper
    @axe = UITest::Axe.new(@udid)
    @instance_setup = UITest::InstanceSetup.new(@axe)
  end

  after(:all) do
    # Terminate app
    UITest::App.terminate(udid: @udid, silent: true) if @udid

    # Shutdown simulator unless --keep-simulator
    UITest::Simulator.shutdown(@udid) if @udid && !UITest::Config.keep_simulator?
  end

  describe 'adding via Detect & Add' do
    it 'adds Invidious instance and verifies it appears in Sources' do
      invidious_url = UITest::Config.invidious_url
      invidious_host = UITest::Config.invidious_host

      # Ensure we start from Library (check for text since inlineLarge title has no AXUniqueId)
      expect(@axe).to have_text('Library')

      # Remove existing instance (if any) and add fresh - always tests the add flow
      @instance_setup.remove_and_add_invidious(invidious_url)

      # Navigate to Sources to verify the instance was added
      # Open Settings using accessibility identifier
      @axe.tap_id('library.settingsButton')
      sleep 1

      expect(@axe).to have_element('settings.view')

      # Navigate to Sources
      @axe.tap_id('settings.row.sources')
      sleep 0.5

      # Verify we're on Sources list
      expect(@axe).to have_element('sources.view')

      # Verify instance appears in Sources list
      expect(@axe).to have_element("sources.row.invidious.#{invidious_host}")

      # Close settings
      begin
        @axe.tap_label('Done')
      rescue StandardError
        nil
      end
      sleep 0.5
    end
  end
end
