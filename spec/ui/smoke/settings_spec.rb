# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'Settings', :smoke do
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

    # Initialize AXe
    @axe = UITest::Axe.new(@udid)
  end

  after(:all) do
    # Terminate app
    UITest::App.terminate(udid: @udid, silent: true) if @udid

    # Shutdown simulator unless --keep-simulator
    UITest::Simulator.shutdown(@udid) if @udid && !UITest::Config.keep_simulator?
  end

  describe 'opening Settings from Library' do
    before(:all) do
      # Ensure we're on Library tab first (check for text since inlineLarge title has no AXUniqueId)
      expect(@axe).to have_text('Library')

      # Tap Settings button using accessibility identifier
      @axe.tap_id('library.settingsButton')
      sleep 1
    end

    after(:all) do
      # Close Settings to return to Library
      begin
        @axe.tap_label('Done')
      rescue StandardError
        nil
      end
      sleep 0.5
    end

    it 'opens the Settings view' do
      expect(@axe).to have_element('settings.view')
    end

    it 'displays the Settings title' do
      expect(@axe).to have_text('Settings')
    end

    it 'displays the Done button' do
      expect(@axe).to have_element('settings.doneButton')
    end

    it 'displays the Sources section' do
      expect(@axe).to have_text('Sources')
    end

    it 'displays the Playback section' do
      expect(@axe).to have_text('Playback')
    end

    it 'displays the Appearance section' do
      expect(@axe).to have_text('Appearance')
    end

    it 'matches the baseline screenshot', :visual do
      screenshot = @axe.screenshot('settings-main')
      expect(screenshot).to match_baseline
    end
  end

  describe 'closing Settings' do
    before(:all) do
      # Open settings if not already open
      unless @axe.element_exists?('settings.view')
        @axe.tap_id('library.settingsButton')
        sleep 1
      end
    end

    it 'closes Settings when tapping Done' do
      # Verify we're in Settings
      expect(@axe).to have_element('settings.view')

      # Tap Done
      @axe.tap_label('Done')
      sleep 0.5

      # Verify we're back on Library (check for text since inlineLarge title has no AXUniqueId)
      expect(@axe).to have_text('Library')
      expect(@axe).not_to have_element('settings.view')
    end
  end
end
