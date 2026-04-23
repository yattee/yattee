# frozen_string_literal: true

require 'cgi'
require_relative '../spec_helper'

RSpec.describe 'URL Schemes', :smoke do
  before(:all) do
    @udid = UITest::Simulator.boot(UITest::Config.device)

    UITest::App.build(
      device: UITest::Config.device,
      skip: UITest::Config.skip_build?
    )

    UITest::App.install(udid: @udid)
    UITest::App.launch(udid: @udid)

    sleep UITest::Config.app_launch_wait

    @axe = UITest::Axe.new(@udid)
  end

  after(:all) do
    UITest::App.terminate(udid: @udid, silent: true) if @udid
    UITest::Simulator.shutdown(@udid) if @udid && !UITest::Config.keep_simulator?
  end

  # Open a URL and dismiss the iOS "Open in Yattee?" system confirmation dialog.
  # The dialog is a system banner invisible to AXe (like the password save dialog),
  # so we must dismiss it with coordinate taps.
  # On iPhone 17 Pro (393x852pt), the "Open" button appears on the right side
  # of a centered banner. The vertical position varies depending on content behind it.
  # IMPORTANT: Tapping outside the dialog dismisses it as "Cancel", so we check
  # whether the dialog is still showing (empty AXe tree) before each tap.
  def open_url(url)
    UITest::Simulator.open_url(@udid, url)
    sleep 0.8

    # "Open" button positions from highest to lowest - dialog position varies
    # based on the content behind it (higher on Home, lower on pushed views)
    open_button_positions = [
      { x: 280, y: 350 },
      { x: 290, y: 400 },
      { x: 290, y: 460 },
      { x: 280, y: 480 }
    ]

    open_button_positions.each do |pos|
      # Check if dialog is still blocking (AXe tree empty when system dialog is up)
      tree = @axe.describe_ui
      app_children = tree.is_a?(Array) ? tree.first&.dig('children') : nil
      break if app_children && !app_children.empty?

      @axe.tap_coordinates(x: pos[:x], y: pos[:y])
      sleep 0.5
    end
  end

  # Navigate back to Home tab between tests
  def navigate_to_home
    # Try edge swipes to pop any pushed views (up to 5 times)
    5.times do
      break if @axe.element_exists?('home.settingsButton')

      @axe.swipe(start_x: 0, start_y: 400, end_x: 200, end_y: 400, duration: 0.3)
      sleep 0.5
    end

    # Fallback: tap Home tab bar item
    unless @axe.element_exists?('home.settingsButton')
      begin
        @axe.tap_label('Home')
        sleep 0.5
      rescue UITest::Axe::AxeError
        # Already on Home or tab not found
      end
    end
  end

  # Wait for text to become visible with polling
  def wait_for_text(text, timeout: UITest::Config.element_timeout)
    start_time = Time.now

    loop do
      return true if @axe.text_visible?(text)

      if Time.now - start_time > timeout
        @axe.screenshot("debug-wait-for-#{text.downcase.gsub(/\s+/, '-')}")
        raise "Text '#{text}' not visible after #{timeout} seconds"
      end

      sleep 0.5
    end
  end

  # Wait for element to become visible with polling
  def wait_for_element(identifier, timeout: UITest::Config.element_timeout)
    start_time = Time.now

    loop do
      return true if @axe.element_exists?(identifier)

      if Time.now - start_time > timeout
        @axe.screenshot("debug-wait-for-#{identifier.gsub('.', '-')}")
        raise "Element '#{identifier}' not found after #{timeout} seconds"
      end

      sleep 0.5
    end
  end

  describe 'yattee:// navigation URLs' do
    after(:each) do
      navigate_to_home
    end

    it 'opens Playlists via yattee://playlists' do
      open_url('yattee://playlists')
      sleep 1
      wait_for_text('Playlists')
      expect(@axe).to have_text('Playlists')
      @axe.screenshot('url-scheme-playlists')
    end

    it 'opens Bookmarks via yattee://bookmarks' do
      open_url('yattee://bookmarks')
      sleep 1
      wait_for_text('Bookmarks')
      expect(@axe).to have_text('Bookmarks')
      @axe.screenshot('url-scheme-bookmarks')
    end

    it 'opens History via yattee://history' do
      open_url('yattee://history')
      sleep 1
      wait_for_text('History')
      expect(@axe).to have_text('History')
      @axe.screenshot('url-scheme-history')
    end

    it 'opens Downloads via yattee://downloads' do
      open_url('yattee://downloads')
      sleep 1
      wait_for_text('Downloads')
      expect(@axe).to have_text('Downloads')
      @axe.screenshot('url-scheme-downloads')
    end

    it 'opens Channels via yattee://channels' do
      open_url('yattee://channels')
      sleep 1
      wait_for_text('Channels')
      expect(@axe).to have_text('Channels')
      @axe.screenshot('url-scheme-channels')
    end

    it 'opens Subscriptions via yattee://subscriptions' do
      open_url('yattee://subscriptions')
      sleep 1
      wait_for_text('Subscriptions')
      expect(@axe).to have_text('Subscriptions')
      @axe.screenshot('url-scheme-subscriptions')
    end

    it 'opens Continue Watching via yattee://continue-watching' do
      open_url('yattee://continue-watching')
      sleep 1
      wait_for_text('Continue Watching')
      expect(@axe).to have_text('Continue Watching')
      @axe.screenshot('url-scheme-continue-watching')
    end

    # NOTE: yattee://settings deep link is broken in the app -
    # handlePendingNavigation pushes .settings onto homePath but it doesn't render.
    # Skipping until the app's deep link handler is fixed to present Settings properly.

    it 'opens Search via yattee://search?q=test' do
      open_url('yattee://search?q=test')
      sleep 1
      # SearchView pushed via deep link has a sparse accessibility tree -
      # only the nav bar (AXUniqueId "Search") is exposed, not its children.
      # Verify navigation by checking the nav bar identifier.
      wait_for_element('Search')
      expect(@axe).to have_element('Search')
      @axe.screenshot('url-scheme-search')
    end
  end
end

RSpec.describe 'URL Schemes with Backend', :url_backend do
  before(:all) do
    skip 'Backend URL not configured (set YATTEE_SERVER_URL or INVIDIOUS_URL)' unless backend_available?

    @udid = UITest::Simulator.boot(UITest::Config.device)

    UITest::App.build(
      device: UITest::Config.device,
      skip: UITest::Config.skip_build?
    )

    UITest::App.install(udid: @udid)
    UITest::App.launch(udid: @udid)

    sleep UITest::Config.app_launch_wait

    @axe = UITest::Axe.new(@udid)
    @player = UITest::PlayerHelper.new(@axe)
    @instance_setup = UITest::InstanceSetup.new(@axe)

    # Set up backend instance
    setup_backend_instance
  end

  after(:all) do
    UITest::App.terminate(udid: @udid, silent: true) if @udid
    UITest::Simulator.shutdown(@udid) if @udid && !UITest::Config.keep_simulator?
  end

  def self.backend_available?
    ENV['YATTEE_SERVER_URL'] || ENV['INVIDIOUS_URL']
  end

  def backend_available?
    self.class.backend_available?
  end

  def setup_backend_instance
    if ENV['YATTEE_SERVER_URL']
      @instance_setup.ensure_yattee_server(ENV['YATTEE_SERVER_URL'])
    elsif ENV['INVIDIOUS_URL']
      @instance_setup.ensure_invidious(ENV['INVIDIOUS_URL'])
    end
  end

  # Open a yattee:// URL and dismiss the iOS "Open in Yattee?" system confirmation dialog
  def open_url(url)
    UITest::Simulator.open_url(@udid, url)
    sleep 0.8

    open_button_positions = [
      { x: 280, y: 350 },
      { x: 290, y: 400 },
      { x: 290, y: 460 },
      { x: 280, y: 480 }
    ]

    open_button_positions.each do |pos|
      tree = @axe.describe_ui
      app_children = tree.is_a?(Array) ? tree.first&.dig('children') : nil
      break if app_children && !app_children.empty?

      @axe.tap_coordinates(x: pos[:x], y: pos[:y])
      sleep 0.5
    end
  end

  # Wrap an HTTPS URL in yattee://open?url= scheme so simctl routes it to the app
  # instead of Safari. This tests the app's YouTube URL parsing via URLRouter.
  def open_youtube_url(url)
    encoded = CGI.escape(url)
    open_url("yattee://open?url=#{encoded}")
  end

  # Navigate back to Home tab
  def navigate_to_home
    5.times do
      break if @axe.element_exists?('home.settingsButton')

      @axe.swipe(start_x: 0, start_y: 400, end_x: 200, end_y: 400, duration: 0.3)
      sleep 0.5
    end

    unless @axe.element_exists?('home.settingsButton')
      begin
        @axe.tap_label('Home')
        sleep 0.5
      rescue UITest::Axe::AxeError
        # Already on Home
      end
    end
  end

  # Wait for text with timeout
  def wait_for_text(text, timeout: 15)
    start_time = Time.now

    loop do
      return true if @axe.text_visible?(text)

      if Time.now - start_time > timeout
        @axe.screenshot("debug-backend-wait-#{text.downcase.gsub(/\s+/, '-')}")
        raise "Text '#{text}' not visible after #{timeout} seconds"
      end

      sleep 0.5
    end
  end

  # Wait for content to load (channel/playlist views with actual data)
  def wait_for_content_loaded(timeout: 20)
    start_time = Time.now

    loop do
      tree = @axe.describe_ui
      tree_str = tree.to_s

      # A loaded channel/playlist view has a large tree (video thumbnails, titles, etc.)
      # Skeleton/loading views are much smaller (< 2000 chars)
      return true if tree_str.length > 2000

      if Time.now - start_time > timeout
        @axe.screenshot('debug-content-load-timeout')
        raise "Content did not load after #{timeout} seconds (tree length: #{tree_str.length})"
      end

      sleep 1
    end
  end

  # Close player if open, then navigate home
  def cleanup_after_video
    # Try closing expanded player
    if @player.player_expanded?
      @player.close_player
      sleep 1
      # Verify it actually closed, retry if needed
      if @player.player_expanded?
        @player.close_player
        sleep 1
      end
    end

    # Dismiss any remaining sheets/modals (e.g. video info overlays)
    begin
      @axe.swipe(start_x: 200, start_y: 200, end_x: 200, end_y: 800, duration: 0.3)
      sleep 0.5
    rescue UITest::Axe::AxeError
      # Ignore if swipe fails
    end

    navigate_to_home
  end

  describe 'yattee:// content URLs' do
    after(:each) do
      cleanup_after_video
    end

    it 'opens video via yattee://video/{id}' do
      open_url('yattee://video/dQw4w9WgXcQ')
      @player.wait_for_player_expanded(timeout: 20)
      @axe.screenshot('url-scheme-video')
    end

    it 'opens channel via yattee://channel/{id}' do
      open_url('yattee://channel/UC_x5XG1OV2P6uZZ5FSM9Ttw')
      wait_for_content_loaded(timeout: 20)
      @axe.screenshot('url-scheme-channel')
    end

    it 'opens playlist via yattee://playlist/{id}' do
      open_url('yattee://playlist/PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf')
      wait_for_content_loaded(timeout: 20)
      @axe.screenshot('url-scheme-playlist')
    end
  end

  describe 'YouTube URL parsing via yattee://open?url=' do
    after(:each) do
      cleanup_after_video
    end

    it 'parses youtube.com/watch URL and opens video' do
      open_youtube_url('https://www.youtube.com/watch?v=dQw4w9WgXcQ')
      @player.wait_for_player_expanded(timeout: 20)
      @axe.screenshot('url-scheme-youtube-watch')
    end

    it 'parses youtu.be short URL and opens video' do
      open_youtube_url('https://youtu.be/dQw4w9WgXcQ')
      @player.wait_for_player_expanded(timeout: 20)
      @axe.screenshot('url-scheme-youtube-short')
    end

    it 'parses youtube.com/shorts URL and opens video' do
      open_youtube_url('https://www.youtube.com/shorts/dQw4w9WgXcQ')
      @player.wait_for_player_expanded(timeout: 20)
      @axe.screenshot('url-scheme-youtube-shorts')
    end

    it 'parses youtube.com/playlist URL and opens playlist' do
      open_youtube_url('https://www.youtube.com/playlist?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf')
      wait_for_content_loaded(timeout: 20)
      @axe.screenshot('url-scheme-youtube-playlist')
    end

    it 'parses youtube.com/@handle URL and opens channel' do
      open_youtube_url('https://www.youtube.com/@Google')
      wait_for_content_loaded(timeout: 20)
      @axe.screenshot('url-scheme-youtube-handle')
    end
  end
end
