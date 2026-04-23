# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'App Launch', :smoke do
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

  describe 'Home tab' do
    it 'displays the Home navigation bar' do
      expect(@axe).to have_text('Home')
    end

    it 'displays the Tab Bar' do
      expect(@axe).to have_text('Tab Bar')
    end

    it 'displays the Open Link shortcut' do
      expect(@axe).to have_element('home.shortcut.openURL')
    end

    it 'displays the Bookmarks shortcut' do
      expect(@axe).to have_element('home.shortcut.bookmarks')
    end

    it 'displays the History shortcut' do
      expect(@axe).to have_element('home.shortcut.history')
    end

    it 'displays the Settings button' do
      expect(@axe).to have_element('home.settingsButton')
    end

    it 'matches the baseline screenshot', :visual do
      screenshot = @axe.screenshot('app-launch-home')
      expect(screenshot).to match_baseline
    end
  end
end
