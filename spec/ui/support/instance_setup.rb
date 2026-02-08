# frozen_string_literal: true

require 'uri'

module UITest
  # Helper for setting up instances in UI tests.
  # Provides methods to navigate through Settings and add/verify instances.
  class InstanceSetup
    # Coordinates for iPhone 17 Pro (393pt width)
    # Settings gear button in Library toolbar (top-right)
    SETTINGS_BUTTON_COORDS = { x: 380, y: 70 }.freeze

    def initialize(axe)
      @axe = axe
    end

    # Check if Yattee Server instance exists by navigating to Sources
    # @param host [String] Host portion of the server URL
    # @return [Boolean] true if instance exists
    def yattee_server_exists?(host)
      navigate_to_sources
      exists = @axe.element_exists?("sources.row.yatteeServer.#{host}")
      close_settings
      exists
    end

    # Add a Yattee Server instance via Detect & Add flow
    # @param url [String] Full URL of the Yattee Server
    def add_yattee_server(url)
      navigate_to_sources

      # Tap Add Source button in toolbar (using coordinates - iOS 26 doesn't expose toolbar buttons in accessibility tree)
      # The button is in the top-right of the navigation bar at approximately (370, 105)
      @axe.tap_coordinates(x: 370, y: 105)
      sleep 0.8

      # Wait for AddSourceView to appear
      wait_for_element('addSource.urlField')

      # Enter URL in text field
      @axe.tap_id('addSource.urlField')
      sleep 0.5
      @axe.type(url)
      sleep 0.5

      # Tap Detect & Add button
      @axe.tap_id('addSource.actionButton')
      sleep 0.5

      # Wait for detection to complete
      # Use longer timeout for first detection (network cold start)
      result = wait_for_detection(timeout: 20)
      raise "Detection failed: #{result}" if result == :error

      # The sheet auto-dismisses on success
      # If we're already back on sources.view, no need to wait or close
      sleep 1.5 unless @axe.element_exists?('sources.view')

      # Close Settings (return to Library)
      close_settings
    end

    # Ensure Yattee Server instance exists (idempotent)
    # @param url [String] Full URL of the Yattee Server
    # @return [Boolean] true if instance was added, false if already existed
    def ensure_yattee_server(url)
      host = URI.parse(url).host

      if yattee_server_exists?(host)
        puts "  Yattee Server instance already exists: #{host}"
        return false
      end

      puts "  Adding Yattee Server instance: #{url}"
      add_yattee_server(url)
      true
    end

    # Remove Yattee Server instance if it exists, then add it fresh
    # @param url [String] Full URL of the Yattee Server
    def remove_and_add_yattee_server(url)
      host = URI.parse(url).host

      if yattee_server_exists?(host)
        puts "  Removing existing Yattee Server instance: #{host}"
        remove_yattee_server(host)
      end

      puts "  Adding Yattee Server instance: #{url}"
      add_yattee_server(url)
    end

    # Remove a Yattee Server instance by host
    # @param host [String] Host portion of the server URL
    def remove_yattee_server(host)
      remove_instance("sources.row.yatteeServer.#{host}", host)
    end

    # Check if Invidious instance exists by navigating to Sources
    # @param host [String] Host portion of the server URL
    # @return [Boolean] true if instance exists
    def invidious_exists?(host)
      navigate_to_sources
      exists = @axe.element_exists?("sources.row.invidious.#{host}")
      close_settings
      exists
    end

    # Add an Invidious instance via Detect & Add flow
    # @param url [String] Full URL of the Invidious instance
    def add_invidious(url)
      add_instance(url)
    end

    # Ensure Invidious instance exists (idempotent)
    # @param url [String] Full URL of the Invidious instance
    # @return [Boolean] true if instance was added, false if already existed
    def ensure_invidious(url)
      host = URI.parse(url).host

      if invidious_exists?(host)
        puts "  Invidious instance already exists: #{host}"
        return false
      end

      puts "  Adding Invidious instance: #{url}"
      add_invidious(url)
      true
    end

    # Remove Invidious instance if it exists, then add it fresh
    # @param url [String] Full URL of the Invidious instance
    def remove_and_add_invidious(url)
      host = URI.parse(url).host

      if invidious_exists?(host)
        puts "  Removing existing Invidious instance: #{host}"
        remove_invidious(host)
      end

      puts "  Adding Invidious instance: #{url}"
      add_invidious(url)
    end

    # Remove an Invidious instance by host
    # @param host [String] Host portion of the server URL
    def remove_invidious(host)
      remove_instance("sources.row.invidious.#{host}", host)
    end

    # Check if logged in to Invidious instance
    # @param host [String] Host portion of the server URL
    # @return [Boolean] true if logged in
    def invidious_logged_in?(host)
      navigate_to_sources

      # Tap on Invidious instance row to open EditSourceView
      # Due to iOS 26 accessibility issues, use coordinates from the element
      tap_first_element_with_id("sources.row.invidious.#{host}")
      sleep 0.8

      # Check if "Log Out" is visible (indicates logged in)
      logged_in = @axe.text_visible?('Log Out')

      # Close the edit sheet
      close_edit_sheet

      logged_in
    end

    # Log in to Invidious instance
    # @param host [String] Host portion of the server URL
    # @return [Boolean] true if login succeeded
    def login_invidious(host)
      email = Config.invidious_email
      password = Config.invidious_password

      raise 'Invidious credentials not configured (set INVIDIOUS_EMAIL and INVIDIOUS_PASSWORD)' unless email && password

      navigate_to_sources

      # Tap on Invidious instance row to open EditSourceView
      # Due to iOS 26 accessibility issues, use coordinates from the element
      tap_first_element_with_id("sources.row.invidious.#{host}")
      sleep 0.8

      # Wait for EditSourceView
      wait_for_element('editSource.view')

      # Tap Log in button
      @axe.tap_label('Log in to Account')
      sleep 0.8

      # Wait for login sheet
      wait_for_element('instance.login.view')

      # Enter email/username
      @axe.tap_id('instance.login.usernameField')
      sleep 0.3
      @axe.type(email)
      sleep 0.3

      # Enter password
      @axe.tap_id('instance.login.passwordField')
      sleep 0.3
      @axe.type(password)
      sleep 0.3

      # Tap Sign In button
      @axe.tap_id('instance.login.submitButton')

      # Wait for login to complete (login sheet dismisses, back to edit view)
      start_time = Time.now
      dismiss_attempts = 0
      loop do
        elapsed = (Time.now - start_time).round(1)

        # Check if login succeeded (logout button visible)
        if @axe.text_visible?('Log Out')
          puts "  [#{elapsed}s] Found Log Out button"
          break
        end

        # Check for error
        if @axe.element_exists?('instance.login.error')
          puts '  Login failed with error'
          close_edit_sheet
          return false
        end

        # The iOS "Save Password?" dialog is a system dialog that blocks the accessibility tree
        # When it appears, the app's children become empty or show different content
        tree = @axe.describe_ui
        app_children = tree.is_a?(Array) ? tree.first&.dig('children') : nil
        app_has_no_children = app_children.nil? || app_children.empty?

        # Also check if we're stuck (not on login view, not on edit view with Log Out)
        has_login_view = find_first_element_with_id(tree, 'instance.login.view')

        # Detect password dialog: either empty children OR we're past the login view but don't see Log Out
        password_dialog_likely = app_has_no_children || (!has_login_view && !@axe.text_visible?('Log Out') && elapsed > 1.5)

        if password_dialog_likely && elapsed > 1.0 && dismiss_attempts < 20
          puts "  [#{elapsed}s] Password dialog likely blocking, attempting dismiss ##{dismiss_attempts + 1}..."
          # Try different approaches to dismiss the password save dialog
          # The iOS "Save Password?" dialog appears at bottom of screen
          # "Not Now" button is typically on the left side of the dialog
          case dismiss_attempts
          when 0
            # Try "Not Now" button - bottom left area for iPhone 17 Pro (393pt width, 852pt height)
            @axe.tap_coordinates(x: 100, y: 750)
          when 1
            # Slightly higher
            @axe.tap_coordinates(x: 100, y: 720)
          when 2
            # Slightly to the right
            @axe.tap_coordinates(x: 130, y: 735)
          when 3
            # Try more to the left
            @axe.tap_coordinates(x: 80, y: 740)
          when 4
            # Try different vertical position
            @axe.tap_coordinates(x: 100, y: 700)
          when 5
            # Try center-left
            @axe.tap_coordinates(x: 120, y: 710)
          when 6
            # Try tapping outside the dialog area
            @axe.tap_coordinates(x: 200, y: 100)
          when 7
            # Try swipe down to dismiss
            @axe.swipe(start_x: 200, start_y: 600, end_x: 200, end_y: 800, duration: 0.3)
          when 8
            # Try Return key which might select default
            @axe.press_key(40)
          when 9
            # Try more coordinates
            @axe.tap_coordinates(x: 90, y: 730)
          when 10
            # Upper part of dialog
            @axe.tap_coordinates(x: 100, y: 680)
          when 11
            # Try space key
            @axe.press_key(44)
          when 12
            # More attempts at common positions
            @axe.tap_coordinates(x: 110, y: 725)
          when 13
            # Tab key to move focus, then enter
            @axe.press_key(43)
            sleep 0.2
            @axe.press_key(40)
          when 14
            # Try ESC key
            @axe.press_key(41)
          when 15
            # Try coordinates for larger dialog variant
            @axe.tap_coordinates(x: 100, y: 780)
          when 16
            # Try far left
            @axe.tap_coordinates(x: 50, y: 740)
          when 17
            # Try middle of screen
            @axe.tap_coordinates(x: 200, y: 740)
          when 18
            # Swipe up
            @axe.swipe(start_x: 200, start_y: 750, end_x: 200, end_y: 400, duration: 0.3)
          when 19
            # Final ESC attempt
            @axe.press_key(41)
          end
          dismiss_attempts += 1
          sleep 0.5
          next
        end

        if Time.now - start_time > 35
          # Dump UI tree for debugging
          puts '  Login timed out - dumping UI tree:'
          puts tree.to_s[0..3000]
          raise 'Login timed out'
        end

        sleep 0.5
      end

      puts '  Login succeeded'

      # Close edit sheet and return to Library
      # After successful login, we're on EditSourceView - need to go back to Sources
      # Try Back button first (for navigation-based sheets)
      begin
        @axe.tap_label('Back')
        sleep 0.5
      rescue UITest::Axe::AxeError
        # Try swipe to go back (edge swipe from left)
        @axe.swipe(start_x: 0, start_y: 400, end_x: 200, end_y: 400, duration: 0.3)
        sleep 0.5
      end

      # Now close the Settings sheet
      close_settings
      sleep 0.5

      # Verify we're back on Library, attempt recovery if not
      unless @axe.text_visible?('Library') || @axe.element_exists?('library.card.playlists')
        dismiss_any_sheets
        sleep 0.5
      end

      true
    end

    # Ensure logged in to Invidious (idempotent)
    # @param host [String] Host portion of the server URL
    # @return [Boolean] true if login was performed, false if already logged in
    def ensure_invidious_logged_in(host)
      if invidious_logged_in?(host)
        puts "  Already logged in to Invidious: #{host}"
        return false
      end

      puts "  Logging in to Invidious: #{host}"
      login_invidious(host)
      true
    end

    # Check if Piped instance exists by navigating to Sources
    # @param host [String] Host portion of the server URL
    # @return [Boolean] true if instance exists
    def piped_exists?(host)
      navigate_to_sources
      exists = @axe.element_exists?("sources.row.piped.#{host}")
      close_settings
      exists
    end

    # Add a Piped instance via Detect & Add flow
    # @param url [String] Full URL of the Piped instance
    def add_piped(url)
      add_instance(url)
    end

    # Ensure Piped instance exists (idempotent)
    # @param url [String] Full URL of the Piped instance
    # @return [Boolean] true if instance was added, false if already existed
    def ensure_piped(url)
      host = URI.parse(url).host

      if piped_exists?(host)
        puts "  Piped instance already exists: #{host}"
        return false
      end

      puts "  Adding Piped instance: #{url}"
      add_piped(url)
      true
    end

    # Remove Piped instance if it exists, then add it fresh
    # @param url [String] Full URL of the Piped instance
    def remove_and_add_piped(url)
      host = URI.parse(url).host

      if piped_exists?(host)
        puts "  Removing existing Piped instance: #{host}"
        remove_piped(host)
      end

      puts "  Adding Piped instance: #{url}"
      add_piped(url)
    end

    # Remove a Piped instance by host
    # @param host [String] Host portion of the server URL
    def remove_piped(host)
      remove_instance("sources.row.piped.#{host}", host)
    end

    # Check if logged in to Piped instance
    # @param host [String] Host portion of the server URL
    # @return [Boolean] true if logged in
    def piped_logged_in?(host)
      navigate_to_sources

      # Tap on Piped instance row to open EditSourceView
      # Due to iOS 26 accessibility issues, use coordinates from the element
      tap_first_element_with_id("sources.row.piped.#{host}")
      sleep 0.8

      # Check if "Log Out" is visible (indicates logged in)
      logged_in = @axe.text_visible?('Log Out')

      # Close the edit sheet
      close_edit_sheet

      logged_in
    end

    # Log in to Piped instance
    # @param host [String] Host portion of the server URL
    # @return [Boolean] true if login succeeded
    def login_piped(host)
      username = Config.piped_username
      password = Config.piped_password

      raise 'Piped credentials not configured (set PIPED_USERNAME and PIPED_PASSWORD)' unless username && password

      navigate_to_sources

      # Tap on Piped instance row to open EditSourceView
      # Due to iOS 26 accessibility issues, use coordinates from the element
      tap_first_element_with_id("sources.row.piped.#{host}")
      sleep 0.8

      # Wait for EditSourceView
      wait_for_element('editSource.view')

      # Tap Log in button
      @axe.tap_label('Log in to Account')
      sleep 0.8

      # Wait for login sheet
      wait_for_element('instance.login.view')

      # Enter username (Piped uses username, not email)
      @axe.tap_id('instance.login.usernameField')
      sleep 0.3
      @axe.type(username)
      sleep 0.3

      # Enter password
      @axe.tap_id('instance.login.passwordField')
      sleep 0.3
      @axe.type(password)
      sleep 0.3

      # Tap Sign In button
      @axe.tap_id('instance.login.submitButton')

      # Wait for login to complete (login sheet dismisses, back to edit view)
      start_time = Time.now
      dismiss_attempts = 0
      loop do
        elapsed = (Time.now - start_time).round(1)

        # Check if login succeeded (logout button visible)
        if @axe.text_visible?('Log Out')
          puts "  [#{elapsed}s] Found Log Out button"
          break
        end

        # Check for error
        if @axe.element_exists?('instance.login.error')
          puts '  Login failed with error'
          close_edit_sheet
          return false
        end

        # The iOS "Save Password?" dialog is a system dialog that blocks the accessibility tree
        # When it appears, the app's children become empty or show different content
        tree = @axe.describe_ui
        app_children = tree.is_a?(Array) ? tree.first&.dig('children') : nil
        app_has_no_children = app_children.nil? || app_children.empty?

        # Also check if we're stuck (not on login view, not on edit view with Log Out)
        has_login_view = find_first_element_with_id(tree, 'instance.login.view')

        # Detect password dialog: either empty children OR we're past the login view but don't see Log Out
        password_dialog_likely = app_has_no_children || (!has_login_view && !@axe.text_visible?('Log Out') && elapsed > 1.5)

        if password_dialog_likely && elapsed > 1.0 && dismiss_attempts < 20
          puts "  [#{elapsed}s] Password dialog likely blocking, attempting dismiss ##{dismiss_attempts + 1}..."
          # Try different approaches to dismiss the password save dialog
          # The iOS "Save Password?" dialog appears at bottom of screen
          # "Not Now" button is typically on the left side of the dialog
          case dismiss_attempts
          when 0
            # Try "Not Now" button - bottom left area for iPhone 17 Pro (393pt width, 852pt height)
            @axe.tap_coordinates(x: 100, y: 750)
          when 1
            # Slightly higher
            @axe.tap_coordinates(x: 100, y: 720)
          when 2
            # Slightly to the right
            @axe.tap_coordinates(x: 130, y: 735)
          when 3
            # Try more to the left
            @axe.tap_coordinates(x: 80, y: 740)
          when 4
            # Try different vertical position
            @axe.tap_coordinates(x: 100, y: 700)
          when 5
            # Try center-left
            @axe.tap_coordinates(x: 120, y: 710)
          when 6
            # Try tapping outside the dialog area
            @axe.tap_coordinates(x: 200, y: 100)
          when 7
            # Try swipe down to dismiss
            @axe.swipe(start_x: 200, start_y: 600, end_x: 200, end_y: 800, duration: 0.3)
          when 8
            # Try Return key which might select default
            @axe.press_key(40)
          when 9
            # Try more coordinates
            @axe.tap_coordinates(x: 90, y: 730)
          when 10
            # Upper part of dialog
            @axe.tap_coordinates(x: 100, y: 680)
          when 11
            # Try space key
            @axe.press_key(44)
          when 12
            # More attempts at common positions
            @axe.tap_coordinates(x: 110, y: 725)
          when 13
            # Tab key to move focus, then enter
            @axe.press_key(43)
            sleep 0.2
            @axe.press_key(40)
          when 14
            # Try ESC key
            @axe.press_key(41)
          when 15
            # Try coordinates for larger dialog variant
            @axe.tap_coordinates(x: 100, y: 780)
          when 16
            # Try far left
            @axe.tap_coordinates(x: 50, y: 740)
          when 17
            # Try middle of screen
            @axe.tap_coordinates(x: 200, y: 740)
          when 18
            # Swipe up
            @axe.swipe(start_x: 200, start_y: 750, end_x: 200, end_y: 400, duration: 0.3)
          when 19
            # Final ESC attempt
            @axe.press_key(41)
          end
          dismiss_attempts += 1
          sleep 0.5
          next
        end

        if Time.now - start_time > 35
          # Dump UI tree for debugging
          puts '  Login timed out - dumping UI tree:'
          puts tree.to_s[0..3000]
          raise 'Login timed out'
        end

        sleep 0.5
      end

      puts '  Login succeeded'

      # Close edit sheet and return to Library
      # After successful login, we're on EditSourceView - need to go back to Sources
      # Try Back button first (for navigation-based sheets)
      begin
        @axe.tap_label('Back')
        sleep 0.5
      rescue UITest::Axe::AxeError
        # Try swipe to go back (edge swipe from left)
        @axe.swipe(start_x: 0, start_y: 400, end_x: 200, end_y: 400, duration: 0.3)
        sleep 0.5
      end

      # Now close the Settings sheet
      close_settings
      sleep 0.5

      # Verify we're back on Library, attempt recovery if not
      unless @axe.text_visible?('Library') || @axe.element_exists?('library.card.playlists')
        dismiss_any_sheets
        sleep 0.5
      end

      true
    end

    # Ensure logged in to Piped (idempotent)
    # @param host [String] Host portion of the server URL
    # @return [Boolean] true if login was performed, false if already logged in
    def ensure_piped_logged_in(host)
      if piped_logged_in?(host)
        puts "  Already logged in to Piped: #{host}"
        return false
      end

      puts "  Logging in to Piped: #{host}"
      login_piped(host)
      true
    end

    private

    # Close edit source sheet and return to sources list
    def close_edit_sheet
      # Try Cancel button first
      begin
        @axe.tap_label('Cancel')
        sleep 0.5
        return if @axe.element_exists?('sources.view')
      rescue UITest::Axe::AxeError
        # Not found
      end

      # Try swipe down
      @axe.swipe(start_x: 200, start_y: 300, end_x: 200, end_y: 700, duration: 0.3)
      sleep 0.5
    end

    # Tap the first element matching an accessibility identifier
    # iOS 26 sometimes returns multiple elements with the same ID (e.g., row children)
    # This finds the first one and taps its center coordinates
    # @param identifier [String] The accessibility identifier to find
    def tap_first_element_with_id(identifier)
      tree = @axe.describe_ui
      element = find_first_element_with_id(tree, identifier)
      raise UITest::Axe::AxeError, "No element found with id '#{identifier}'" unless element

      frame = element['frame']
      x = frame['x'] + (frame['width'] / 2)
      y = frame['y'] + (frame['height'] / 2)
      @axe.tap_coordinates(x: x, y: y)
    end

    # Recursively find the first element with a matching AXUniqueId
    # @param node [Hash, Array] Current node in the tree
    # @param identifier [String] The identifier to match
    # @return [Hash, nil] The element or nil if not found
    def find_first_element_with_id(node, identifier)
      case node
      when Hash
        return node if node['AXUniqueId'] == identifier

        node.each_value do |value|
          result = find_first_element_with_id(value, identifier)
          return result if result
        end
      when Array
        node.each do |item|
          result = find_first_element_with_id(item, identifier)
          return result if result
        end
      end
      nil
    end

    # Generic method to add an instance via Detect & Add flow
    # @param url [String] Full URL of the instance
    def add_instance(url)
      navigate_to_sources

      # Tap Add Source button in toolbar (using coordinates - iOS 26 doesn't expose toolbar buttons in accessibility tree)
      # The button is in the top-right of the navigation bar at approximately (370, 105)
      @axe.tap_coordinates(x: 370, y: 105)
      sleep 0.8

      # Wait for AddSourceView to appear
      wait_for_element('addSource.urlField')

      # Enter URL in text field
      @axe.tap_id('addSource.urlField')
      sleep 0.5
      @axe.type(url)
      sleep 0.5

      # Tap Detect & Add button
      @axe.tap_id('addSource.actionButton')
      sleep 0.5

      # Wait for detection to complete
      # Use longer timeout for first detection (network cold start)
      result = wait_for_detection(timeout: 20)
      raise "Detection failed: #{result}" if result == :error

      # The sheet auto-dismisses on success
      # If we're already back on sources.view, no need to wait or close
      sleep 1.5 unless @axe.element_exists?('sources.view')

      # Close Settings (return to Library)
      close_settings
    end

    # Generic method to remove an instance by row ID
    # @param row_id [String] Full accessibility identifier for the row
    # @param host [String] Host name for logging
    # @return [Boolean] true if removed, false if not found
    def remove_instance(row_id, host)
      navigate_to_sources

      # Verify the row exists
      unless @axe.element_exists?(row_id)
        puts "  Instance not found: #{host}"
        close_settings
        return false
      end

      # Swipe left on the row to reveal delete button
      # First, find approximate position of the row (middle of screen, adjust as needed)
      @axe.swipe(start_x: 350, start_y: 200, end_x: 50, end_y: 200, duration: 0.3)
      sleep 0.3

      # Tap the Delete button that appears
      begin
        @axe.tap_label('Delete')
        sleep 0.5
      rescue UITest::Axe::AxeError
        # Try tapping by coordinates if label doesn't work
        @axe.tap_coordinates(x: 370, y: 200)
        sleep 0.5
      end

      # Close Settings
      close_settings
      true
    end

    # Navigate from Library to Settings > Sources
    def navigate_to_sources
      # Ensure we're on Library tab
      ensure_on_library

      # Tap Settings button using accessibility identifier
      @axe.tap_id('library.settingsButton')
      sleep 1

      # Wait for Settings view
      wait_for_element('settings.view')

      # Tap Sources row
      @axe.tap_id('settings.row.sources')
      sleep 0.5

      # Wait for Sources list view
      wait_for_element('sources.view')
    end

    # Ensure we're on the Library tab
    def ensure_on_library
      # Check for Library navigation title (text, since inlineLarge has no AXUniqueId) or a library card
      return if @axe.text_visible?('Library') || @axe.element_exists?('library.card.playlists')

      # Try to dismiss any sheets/modals
      dismiss_any_sheets

      # Final check - use a longer timeout
      wait_for_library
    end

    # Try various methods to dismiss sheets/modals
    def dismiss_any_sheets
      # Try Done button by ID
      begin
        @axe.tap_id('settings.doneButton')
        sleep 0.5
        return if @axe.text_visible?('Library') || @axe.element_exists?('library.card.playlists')
      rescue UITest::Axe::AxeError
        # Not found
      end

      # Try Done by label
      begin
        @axe.tap_label('Done')
        sleep 0.5
        return if @axe.text_visible?('Library') || @axe.element_exists?('library.card.playlists')
      rescue UITest::Axe::AxeError
        # Not found
      end

      # Try swipe down to dismiss
      @axe.swipe(start_x: 200, start_y: 300, end_x: 200, end_y: 700, duration: 0.3)
      sleep 0.5
      return if @axe.text_visible?('Library') || @axe.element_exists?('library.card.playlists')

      # Last resort: home button
      @axe.home_button
      sleep 1
    end

    # Wait for Library view to appear
    def wait_for_library(timeout: Config.element_timeout)
      start_time = Time.now

      loop do
        # Check for Library title (text, since inlineLarge has no AXUniqueId) or a library card
        return true if @axe.text_visible?('Library') || @axe.element_exists?('library.card.playlists')

        raise "Library not found after #{timeout} seconds" if Time.now - start_time > timeout

        sleep 0.3
      end
    end

    # Close Settings sheet - handles navigation back from sub-views
    def close_settings
      # Try swipe down to dismiss the sheet (most reliable)
      @axe.swipe(start_x: 200, start_y: 300, end_x: 200, end_y: 700, duration: 0.3)
      sleep 0.5
      return if @axe.text_visible?('Library') || @axe.element_exists?('library.card.playlists')

      # Try Done button by ID
      begin
        @axe.tap_id('settings.doneButton')
        sleep 0.5
        return
      rescue UITest::Axe::AxeError
        # Not found
      end

      # Try Done by label
      begin
        @axe.tap_label('Done')
        sleep 0.5
      rescue UITest::Axe::AxeError
        # Not found
      end
    end

    # Wait for detection to complete
    # @param timeout [Integer] Timeout in seconds (default: 20 for network operations)
    # @return [Symbol] :success or :error
    def wait_for_detection(timeout: 20)
      start_time = Time.now

      loop do
        # Check for success (detected type shown)
        if @axe.element_exists?('addSource.detectedType')
          puts "  Detection succeeded after #{(Time.now - start_time).round(1)}s"
          return :success
        end

        # Check for error
        if @axe.element_exists?('addSource.detectionError')
          puts "  Detection failed with error after #{(Time.now - start_time).round(1)}s"
          return :error
        end

        # Check if the AddSourceView sheet was auto-dismissed after successful detection
        # This happens when the instance is added - the sheet closes automatically
        if @axe.element_exists?('sources.view') && !@axe.element_exists?('addSource.urlField')
          puts "  Detection succeeded (sheet auto-dismissed) after #{(Time.now - start_time).round(1)}s"
          return :success
        end

        # Check for timeout
        elapsed = Time.now - start_time
        raise "Detection timed out after #{timeout} seconds" if elapsed > timeout

        sleep 0.5
      end
    end

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
  end
end
