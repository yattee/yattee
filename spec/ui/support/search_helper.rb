# frozen_string_literal: true

module UITest
  # Helper for search functionality in UI tests.
  # Provides methods to navigate to search, enter queries, and interact with results.
  class SearchHelper
    # Coordinates for iPhone 17 Pro (402pt width based on AXe frame data)
    # On iOS 26+ with TabView role: .search, the search field is integrated into the tab bar
    # Search field frame from AXe: {{88, 798}, {286, 48}} - center is approximately (231, 822)
    SEARCH_FIELD_COORDS = { x: 231, y: 822 }.freeze
    # Search tab is on the right side of the tab bar (bottom of screen)
    # Tab bar is at approximately y=815, search tab is rightmost
    SEARCH_TAB_COORDS = { x: 350, y: 815 }.freeze

    def initialize(axe)
      @axe = axe
    end

    # Navigate to Search tab
    def navigate_to_search
      # Try accessibility ID first, fall back to coordinates
      begin
        @axe.tap_id('tab.search')
      rescue UITest::Axe::AxeError
        # Tab accessibility IDs may not work on iOS 26+ tab bars
        # Use coordinates to tap the search tab (rightmost tab)
        puts '  Using coordinates to tap Search tab'
        @axe.tap_coordinates(**SEARCH_TAB_COORDS)
      end
      sleep 1.0

      # Debug: Take screenshot and dump elements to see what's visible
      puts '  [DEBUG] After tapping search tab, checking visible elements...'
      puts "  [DEBUG] text 'search.empty' visible? #{@axe.text_visible?('search.empty')}"
      puts "  [DEBUG] text 'search.recents' visible? #{@axe.text_visible?('search.recents')}"
      puts "  [DEBUG] text 'Search' visible? #{@axe.text_visible?('Search')}"

      # Take debug screenshot
      screenshot_path = @axe.screenshot('debug_after_search_tap')
      puts "  [DEBUG] Screenshot saved to: #{screenshot_path}"

      # Dump accessibility tree for debugging
      puts '  [DEBUG] Dumping accessibility tree labels...'
      tree = @axe.describe_ui
      dump_labels(tree)
      puts '  [DEBUG] End of accessibility tree'

      # The search tab with role: .search on iOS 26+ integrates searchable into tab bar
      # The SearchView content should be visible - try waiting for the search field or view
      wait_for_search_ready
    end

    # Wait for search to be ready (search view, empty state, or recents visible)
    def wait_for_search_ready(timeout: 10)
      start_time = Time.now

      loop do
        # Check for various search view states using accessibility labels
        # (accessibilityIdentifier doesn't work on Group/some SwiftUI views)
        return true if @axe.text_visible?('search.empty')
        return true if @axe.text_visible?('search.recents')

        # Also check for the navigation title "Search" as fallback
        return true if @axe.text_visible?('Search')

        elapsed = Time.now - start_time
        raise "Search not ready after #{timeout} seconds" if elapsed > timeout

        sleep 0.3
      end
    end

    # Check if search view is displayed (any state)
    def search_visible?
      @axe.text_visible?('search.empty') ||
        @axe.text_visible?('search.recents') ||
        @axe.text_visible?('Search')
    end

    # Perform a search query
    # @param query [String] The search query to enter
    def search(query)
      puts "  Searching for: #{query}"

      # First, check if this query exists in recent searches - if so, tap it directly
      if @axe.text_visible?(query)
        puts "  [DEBUG] Found '#{query}' in recent searches, tapping it"
        @axe.tap_label(query)
        sleep 1.0
        @axe.screenshot('debug_after_recent_tap')
        return
      end

      # Take screenshot before tapping search field
      @axe.screenshot('debug_before_search_tap')

      # Try to tap on search field by label first, fall back to coordinates
      begin
        @axe.tap_label('Videos, channels, playlists')
        puts '  [DEBUG] Tapped search field by label'
      rescue UITest::Axe::AxeError
        puts '  [DEBUG] Label tap failed, using coordinates'
        @axe.tap_coordinates(**SEARCH_FIELD_COORDS)
      end
      sleep 0.5

      # Take screenshot after tapping search field
      @axe.screenshot('debug_after_search_field_tap')

      # Type the query
      @axe.type(query)
      sleep 0.3

      # Take screenshot after typing
      @axe.screenshot('debug_after_typing')

      # Submit the search by pressing Return key
      # Using hardware key press instead of typing \n which doesn't work in iOS 26+ searchable
      @axe.press_return
      sleep 1.0

      # Take screenshot after submitting
      screenshot_path = @axe.screenshot('debug_after_search_submit')
      puts "  [DEBUG] After search submit: #{screenshot_path}"
    end

    # Wait for search results to appear
    # @param timeout [Integer] Maximum time to wait in seconds
    def wait_for_results(timeout: 30)
      puts '  Waiting for search results...'
      start_time = Time.now

      loop do
        # Check using accessibility labels (more reliable than identifiers)
        return true if @axe.text_visible?('search.results')

        # Check for no results or error states
        return true if @axe.text_visible?('search.noResults')

        elapsed = Time.now - start_time
        if elapsed > timeout
          # Take debug screenshot before failing
          @axe.screenshot('debug_wait_for_results_timeout')
          raise "Search results not found after #{timeout} seconds"
        end

        sleep 0.5
      end
    end

    # Tap on a specific video by ID
    # @param video_id [String] The video ID to tap
    def tap_video(video_id)
      puts "  Tapping video: #{video_id}"
      @axe.tap_id("video.row.#{video_id}")
      sleep 0.5
    end

    # Tap the first video result by coordinates (text area - opens info)
    # Used when individual video rows aren't accessible via accessibility tree
    def tap_first_result
      puts '  Tapping first search result by coordinates'
      # First result is below filter strip (y≈122) with padding
      # Video row center is approximately y=230 for first result
      @axe.tap_coordinates(x: 200, y: 230)
      sleep 0.5
    end

    # Tap the first video thumbnail to start playback directly
    # Thumbnail is on the left side of the video row
    def tap_first_result_thumbnail
      puts '  Tapping first search result thumbnail to play'
      # First result thumbnail is at approximately:
      # x: 100 (center of thumbnail on left side)
      # y: 180 (first result row)
      @axe.tap_coordinates(x: 100, y: 180)
      sleep 0.5
    end

    # Check if a video exists in results
    # @param video_id [String] The video ID to check
    # @return [Boolean] true if the video exists in results
    def video_exists?(video_id)
      @axe.text_visible?("video.row.#{video_id}")
    end

    # Wait for a specific video to appear in results
    # @param video_id [String] The video ID to wait for
    # @param timeout [Integer] Timeout in seconds
    def wait_for_video(video_id, timeout: 30)
      puts "  Waiting for video: #{video_id}"
      start_time = Time.now

      loop do
        return true if video_exists?(video_id)

        elapsed = Time.now - start_time
        if elapsed > timeout
          @axe.screenshot('debug_wait_for_video_timeout')
          raise "Video '#{video_id}' not found after #{timeout} seconds"
        end

        sleep 0.5
      end
    end

    # Check if search results are displayed
    # @return [Boolean] true if results are visible
    def results_visible?
      @axe.text_visible?('search.results')
    end

    # Check if no results message is displayed
    # @return [Boolean] true if no results message is visible
    def no_results_visible?
      @axe.element_exists?('search.noResults')
    end

    # Check if search is loading
    # @return [Boolean] true if loading indicator is visible
    def loading?
      @axe.element_exists?('search.loading')
    end

    private

    # Wait for an element to appear
    # @param identifier [String] Accessibility identifier
    # @param timeout [Integer] Timeout in seconds
    def wait_for_element(identifier, timeout: Config.element_timeout)
      start_time = Time.now

      loop do
        return true if @axe.element_exists?(identifier)

        raise "Element '#{identifier}' not found after #{timeout} seconds" if Time.now - start_time > timeout

        sleep 0.3
      end
    end

    # Debug helper to dump accessibility labels from tree
    def dump_labels(node, depth = 0, max_depth = 10)
      return if depth > max_depth

      case node
      when Hash
        id = node['AXUniqueId']
        label = node['AXLabel']
        role = node['AXRole']
        indent = '  ' * depth
        puts "#{indent}[Role: #{role}] [ID: #{id}] [Label: #{label}]" if id || label || role
        node.each_value { |v| dump_labels(v, depth + 1, max_depth) }
      when Array
        node.each { |item| dump_labels(item, depth, max_depth) }
      end
    end
  end
end
