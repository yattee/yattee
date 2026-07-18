# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'Search and play on basic-auth Invidious', :smoke do
  before(:all) do
    skip 'INVIDIOUS_BASIC_AUTH_USERNAME / _PASSWORD not set' unless UITest::Config.invidious_basic_auth_credentials?

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

    # Make the basic-auth Invidious instance the only Invidious-compatible source
    # so search and playback route through the reverse proxy.
    @instance_setup.remove_yattee_server(UITest::Config.yattee_server_host)
    @instance_setup.remove_and_add_invidious_with_basic_auth(
      UITest::Config.invidious_basic_auth_url,
      username: UITest::Config.invidious_basic_auth_username,
      password: UITest::Config.invidious_basic_auth_password
    )
  end

  after(:all) do
    UITest::App.terminate(udid: @udid, silent: true) if @udid
    UITest::Simulator.shutdown(@udid) if @udid && !UITest::Config.keep_simulator?
  end

  describe 'searching and playing a video through the basic-auth proxy' do
    it 'searches, taps a video, plays it, and closes the player' do
      video_id = 'XfELJU1mRMg'

      # Navigate to Search and run a query for the known video
      @search_helper.navigate_to_search
      expect(@search_helper.search_visible?).to be true

      @search_helper.search(video_id)
      @search_helper.wait_for_results

      expect(@search_helper.results_visible?).to be true

      # Tap the first result thumbnail to start playback directly
      @search_helper.tap_first_result_thumbnail

      # Wait for the player to expand and start playback
      @player_helper.wait_for_player_expanded
      @player_helper.wait_for_playback_started

      @axe.screenshot('invidious_basic_auth_playback_playing')

      # Close the player
      @player_helper.close_player

      @axe.screenshot('invidious_basic_auth_playback_after_close')
    end
  end
end
