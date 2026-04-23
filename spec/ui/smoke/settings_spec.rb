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

  describe 'opening Settings from Home' do
    before(:all) do
      # Ensure we're on Home tab first
      expect(@axe).to have_text('Home')

      # Tap Settings button using accessibility identifier
      @axe.tap_id('home.settingsButton')
      sleep 1
    end

    after(:all) do
      # Close Settings to return to Home
      begin
        @axe.tap_id('settings.doneButton')
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

    it 'displays the Close button' do
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
    it 'closes Settings when tapping Close' do
      # Ensure we're on Home first
      sleep 0.5
      unless @axe.text_visible?('Home') || @axe.element_exists?('home.settingsButton')
        # Try to dismiss any open sheets
        begin
          @axe.tap_id('settings.doneButton')
          sleep 0.5
        rescue StandardError
          nil
        end
      end

      # Open Settings fresh
      @axe.tap_id('home.settingsButton')
      sleep 1

      # Verify we're in Settings
      expect(@axe).to have_element('settings.view')
      expect(@axe).to have_element('settings.doneButton')

      # Tap Close
      @axe.tap_id('settings.doneButton')
      sleep 1.5

      # Verify we're back on Home
      expect(@axe).to have_text('Home')
      expect(@axe).not_to have_element('settings.view')
    end
  end
end
