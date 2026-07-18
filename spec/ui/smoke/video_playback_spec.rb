# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'Video Playback', :smoke do
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

    # Initialize helpers
    @axe = UITest::Axe.new(@udid)
    @instance_setup = UITest::InstanceSetup.new(@axe)
    @search_helper = UITest::SearchHelper.new(@axe)
    @player_helper = UITest::PlayerHelper.new(@axe)

    # Ensure Yattee Server instance is configured
    @instance_setup.ensure_yattee_server(UITest::Config.yattee_server_url)
  end

  after(:all) do
    # Terminate app
    UITest::App.terminate(udid: @udid, silent: true) if @udid

    # Shutdown simulator unless --keep-simulator
    UITest::Simulator.shutdown(@udid) if @udid && !UITest::Config.keep_simulator?
  end

  describe 'playing video from search' do
    it 'searches, taps video, plays, and closes player' do
      video_id = 'XfELJU1mRMg'

      # Navigate to Search and find video
      @search_helper.navigate_to_search
      @search_helper.search(video_id)
      @search_helper.wait_for_results

      # Verify results view is displayed
      expect(@search_helper.results_visible?).to be true

      # Tap first video result thumbnail to start playback directly
      # Note: Tapping thumbnail plays video, tapping text area opens info
      @search_helper.tap_first_result_thumbnail

      # Wait for player to expand and start playing
      @player_helper.wait_for_player_expanded
      @player_helper.wait_for_playback_started

      # Take screenshot of playback for visual verification
      @axe.screenshot('video_playback_playing')

      # Close the player
      @player_helper.close_player

      # Take screenshot after close attempt
      @axe.screenshot('video_playback_after_close')
    end
  end
end
