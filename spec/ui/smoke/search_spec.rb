# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'Search', :smoke do
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

    # Ensure Yattee Server instance is configured
    @instance_setup.ensure_yattee_server(UITest::Config.yattee_server_url)
  end

  after(:all) do
    # Terminate app
    UITest::App.terminate(udid: @udid, silent: true) if @udid

    # Shutdown simulator unless --keep-simulator
    UITest::Simulator.shutdown(@udid) if @udid && !UITest::Config.keep_simulator?
  end

  describe 'searching for videos' do
    it 'navigates to search, enters query, and displays results' do
      video_id = 'XfELJU1mRMg'

      # Navigate to Search tab
      @search_helper.navigate_to_search
      expect(@search_helper.search_visible?).to be true

      # Search for the known video ID
      @search_helper.search(video_id)

      # Wait for results view to appear (filter strip + results container)
      @search_helper.wait_for_results

      # Verify results are displayed
      expect(@search_helper.results_visible?).to be true

      # Take a screenshot for visual verification
      # Note: Individual video rows aren't exposed in iOS accessibility tree
      # due to ScrollView/LazyVStack limitations
      @axe.screenshot('search_results_final')
    end
  end
end
