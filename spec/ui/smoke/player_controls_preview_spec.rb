# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'Player Controls Preview', :smoke do
  before(:all) do
    @udid = UITest::Simulator.boot(UITest::Config.device)
    UITest::App.build(device: UITest::Config.device, skip: UITest::Config.skip_build?)
    UITest::App.install(udid: @udid)
    UITest::App.launch(udid: @udid)
    sleep UITest::Config.app_launch_wait
    @axe = UITest::Axe.new(@udid)
  end

  after(:all) do
    UITest::App.terminate(udid: @udid, silent: true) if @udid
    UITest::Simulator.shutdown(@udid) if @udid && !UITest::Config.keep_simulator?
  end

  describe 'preview padding comparison' do
    it 'captures Portrait and Landscape screenshots for comparison' do
      # Navigate to Settings tab
      @axe.tap_label('Settings')
      sleep 1

      # Navigate to Player Controls
      @axe.tap_label('Player Controls')
      sleep 1

      # Capture Portrait screenshot (default)
      portrait_path = @axe.screenshot('player_controls_portrait')
      puts "Portrait screenshot: #{portrait_path}"

      # Switch to Landscape preview by tapping the right side of the segmented control
      # The picker is at x=48, width=306, so Landscape segment is around x=280, y=398
      @axe.tap_coordinates(x: 280, y: 398)
      sleep 0.5

      # Capture Landscape screenshot
      landscape_path = @axe.screenshot('player_controls_landscape')
      puts "Landscape screenshot: #{landscape_path}"

      puts "\nScreenshots saved to: #{UITest::Config.current_dir}"
      puts 'Compare these screenshots to verify padding consistency.'
    end
  end
end
