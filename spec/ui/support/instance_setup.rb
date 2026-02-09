# frozen_string_literal: true

require 'uri'

module UITest
  # Helper for setting up instances in UI tests.
  # Provides methods to navigate through Settings and add/verify instances.
  class InstanceSetup
    # Coordinates for iPhone 17 Pro (393pt width)
    # Settings gear button in Home toolbar (top-right)
    SETTINGS_BUTTON_COORDS = { x: 380, y: 70 }.freeze

    def initialize(axe)
      @axe = axe
    end

    # Check if Yattee Server instance exists by navigating to Sources
    # @param host [String] Host portion of the server URL
    # @return [Boolean] true if instance exists
    def yattee_server_exists?(host)
      navigate_to_sources
      exists = @axe.text_visible?(host)
      close_settings
      exists
    end

    # Add a Yattee Server instance via Detect & Add flow
    # @param url [String] Full URL of the Yattee Server
    def add_yattee_server(url)
      navigate_to_sources

      # Tap Add Source button (toolbar or empty state)
      tap_add_source_button
      sleep 0.8

      # Select Remote Server from the source type list
      select_remote_server_tab

      # Wait for URL field to appear
      wait_for_element('addRemoteServer.urlField')

      # Enter URL in text field
      @axe.tap_id('addRemoteServer.urlField')
      sleep 0.5
      @axe.type(url)
      sleep 0.5

      # Tap Detect button to identify server type
      @axe.tap_id('addRemoteServer.detectButton')
      sleep 0.5

      # Wait for detection to complete
      result = wait_for_detection(timeout: 20)
      raise "Detection failed: #{result}" if result == :error

      # Enter Yattee Server credentials if available
      username = Config.yattee_server_username
      password = Config.yattee_server_password
      raise 'Yattee Server credentials not configured (set YATTEE_SERVER_USERNAME and YATTEE_SERVER_PASSWORD)' unless username && password

      sleep 0.5

      # Find and fill credential fields by locating text fields after the "Authentication" header
      auth_fields = find_auth_text_fields
      raise 'Could not find username/password fields' if auth_fields.length < 2

      # First field is username, second is password
      username_frame = auth_fields[0]['frame']
      password_frame = auth_fields[1]['frame']

      # Tap and fill username
      @axe.tap_coordinates(
        x: username_frame['x'] + (username_frame['width'] / 2),
        y: username_frame['y'] + (username_frame['height'] / 2)
      )
      sleep 0.3
      @axe.type(username)
      sleep 0.3

      # Tap and fill password
      @axe.tap_coordinates(
        x: password_frame['x'] + (password_frame['width'] / 2),
        y: password_frame['y'] + (password_frame['height'] / 2)
      )
      sleep 0.3
      @axe.type(password)
      sleep 0.3

      # Wait for action button and tap it
      wait_for_element('addRemoteServer.actionButton')
      @axe.tap_id('addRemoteServer.actionButton')
      sleep 0.5

      # Wait for credential validation and sheet dismiss
      wait_for_add_complete(timeout: 20)

      # Close Settings (return to Home)
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
      exists = @axe.text_visible?(host)
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
      tap_element_containing_text(host)
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
      tap_element_containing_text(host)
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

      # Close edit sheet and return to Home
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

      # Verify we're back on Home, attempt recovery if not
      unless @axe.text_visible?('Home') || @axe.element_exists?('home.settingsButton')
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
      exists = @axe.text_visible?(host)
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
      tap_element_containing_text(host)
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
      tap_element_containing_text(host)
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

      # Close edit sheet and return to Home
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

      # Verify we're back on Home, attempt recovery if not
      unless @axe.text_visible?('Home') || @axe.element_exists?('home.settingsButton')
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

    # Tap the first element whose label contains the given text
    # @param text [String] Text to search for in element labels
    def tap_element_containing_text(text)
      tree = @axe.describe_ui
      element = find_element_with_label_text(tree, text)
      raise UITest::Axe::AxeError, "No element found with text '#{text}'" unless element

      frame = element['frame']
      x = frame['x'] + (frame['width'] / 2)
      y = frame['y'] + (frame['height'] / 2)
      @axe.tap_coordinates(x: x, y: y)
    end

    # Recursively find the first element whose AXLabel contains the given text
    def find_element_with_label_text(node, text)
      case node
      when Hash
        if node['AXLabel']&.include?(text) && node['frame']
          return node
        end
        node.each_value do |value|
          result = find_element_with_label_text(value, text)
          return result if result
        end
      when Array
        node.each do |item|
          result = find_element_with_label_text(item, text)
          return result if result
        end
      end
      nil
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

      # Tap Add Source button (toolbar or empty state)
      tap_add_source_button
      sleep 0.8

      # Select Remote Server from the source type list
      select_remote_server_tab

      # Wait for URL field to appear
      wait_for_element('addRemoteServer.urlField')

      # Enter URL in text field
      @axe.tap_id('addRemoteServer.urlField')
      sleep 0.5
      @axe.type(url)
      sleep 0.5

      # Tap Detect button to identify server type
      @axe.tap_id('addRemoteServer.detectButton')
      sleep 0.5

      # Wait for detection to complete
      result = wait_for_detection(timeout: 20)
      raise "Detection failed: #{result}" if result == :error

      # Wait for action button to appear, then tap it
      wait_for_element('addRemoteServer.actionButton')
      @axe.tap_id('addRemoteServer.actionButton')
      sleep 0.5

      # Wait for sheet to dismiss after adding
      wait_for_add_complete(timeout: 20)

      # Close Settings (return to Home)
      close_settings
    end

    # Generic method to remove an instance by host text
    # @param row_id [String] Full accessibility identifier for the row (unused, kept for API compat)
    # @param host [String] Host name for logging and text-based lookup
    # @return [Boolean] true if removed, false if not found
    def remove_instance(row_id, host)
      navigate_to_sources

      # Verify the row exists (using text since accessibilityIdentifier doesn't expose as AXUniqueId)
      unless @axe.text_visible?(host)
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

    # Navigate from Home to Settings > Sources
    def navigate_to_sources
      # Ensure we're on Home tab
      ensure_on_home

      # Tap Settings button using accessibility identifier
      @axe.tap_id('home.settingsButton')
      sleep 1

      # Wait for Settings view
      wait_for_element('settings.view')

      # Tap Sources row
      @axe.tap_id('settings.row.sources')
      sleep 1

      # Wait for Sources list to load
      # sources.view works for empty state (ContentUnavailableView)
      # For populated list, check for the "Remote Servers" section header text
      wait_for_sources_list
    end

    # Ensure we're on the Home tab
    def ensure_on_home
      # Check for Home navigation title or a home element
      return if @axe.text_visible?('Home') || @axe.element_exists?('home.settingsButton')

      # Try to dismiss any sheets/modals
      dismiss_any_sheets

      # Final check - use a longer timeout
      wait_for_home
    end

    # Try various methods to dismiss sheets/modals
    def dismiss_any_sheets
      # Try Done button by ID
      begin
        @axe.tap_id('settings.doneButton')
        sleep 0.5
        return if @axe.text_visible?('Home') || @axe.element_exists?('home.settingsButton')
      rescue UITest::Axe::AxeError
        # Not found
      end

      # Try Done by label
      begin
        @axe.tap_id('settings.doneButton')
        sleep 0.5
        return if @axe.text_visible?('Home') || @axe.element_exists?('home.settingsButton')
      rescue UITest::Axe::AxeError
        # Not found
      end

      # Try swipe down to dismiss
      @axe.swipe(start_x: 200, start_y: 300, end_x: 200, end_y: 700, duration: 0.3)
      sleep 0.5
      return if @axe.text_visible?('Home') || @axe.element_exists?('home.settingsButton')

      # Last resort: home button
      @axe.home_button
      sleep 1
    end

    # Wait for Home view to appear
    def wait_for_home(timeout: Config.element_timeout)
      start_time = Time.now

      loop do
        # Check for Home title or a home element
        return true if @axe.text_visible?('Home') || @axe.element_exists?('home.settingsButton')

        raise "Home not found after #{timeout} seconds" if Time.now - start_time > timeout

        sleep 0.3
      end
    end

    # Close Settings sheet - handles navigation back from sub-views
    def close_settings
      # Try swipe down to dismiss the sheet (most reliable)
      @axe.swipe(start_x: 200, start_y: 300, end_x: 200, end_y: 700, duration: 0.3)
      sleep 0.5
      return if @axe.text_visible?('Home') || @axe.element_exists?('home.settingsButton')

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
        @axe.tap_id('settings.doneButton')
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
        if @axe.element_exists?('addRemoteServer.detectedType')
          puts "  Detection succeeded after #{(Time.now - start_time).round(1)}s"
          return :success
        end

        # Check for error
        if @axe.element_exists?('addRemoteServer.detectionError')
          puts "  Detection failed with error after #{(Time.now - start_time).round(1)}s"
          return :error
        end

        # Check for timeout
        elapsed = Time.now - start_time
        raise "Detection timed out after #{timeout} seconds" if elapsed > timeout

        sleep 0.5
      end
    end

    # Wait for the add source sheet to dismiss after tapping Add Source
    # @param timeout [Integer] Timeout in seconds
    def wait_for_add_complete(timeout: 20)
      start_time = Time.now

      loop do
        # Check if the add form has been dismissed (URL field no longer visible)
        unless @axe.element_exists?('addRemoteServer.urlField')
          puts "  Source added successfully after #{(Time.now - start_time).round(1)}s"
          return
        end

        elapsed = Time.now - start_time
        raise "Adding source timed out after #{timeout} seconds" if elapsed > timeout

        sleep 0.5
      end
    end

    # Wait for Sources list to be visible (works for both empty and populated states)
    def wait_for_sources_list(timeout: Config.element_timeout)
      start_time = Time.now

      loop do
        # Empty state has sources.view on ContentUnavailableView
        return true if @axe.element_exists?('sources.view')

        # Populated state: check for section headers or instance rows
        return true if @axe.text_visible?('Remote Servers')
        return true if @axe.text_visible?('Local & Network')

        raise "Sources list not found after #{timeout} seconds" if Time.now - start_time > timeout

        sleep 0.3
      end
    end

    # Find the authentication text fields (username/password) after the "Authentication" header
    # @return [Array<Hash>] Array of text field elements
    def find_auth_text_fields
      tree = @axe.describe_ui
      fields = []
      found_auth_header = false

      collect_auth_fields = lambda do |node|
        return unless node.is_a?(Hash)

        # Look for "Authentication" heading
        if node['role'] == 'AXHeading' && node['AXLabel']&.include?('Authentication')
          found_auth_header = true
        end

        # Collect text fields after the auth header
        if found_auth_header && node['role'] == 'AXTextField'
          fields << node
        end

        # Stop after finding the action button (past the auth section)
        return if node['AXUniqueId'] == 'addRemoteServer.actionButton'

        (node['children'] || []).each { |child| collect_auth_fields.call(child) }
      end

      if tree.is_a?(Array)
        tree.each { |root| collect_auth_fields.call(root) }
      end

      fields
    end

    # Debug helper to print UI element tree
    def print_element_tree(node, depth = 0)
      return unless node.is_a?(Hash)

      uid = node['AXUniqueId']
      label = node['AXLabel']
      role = node['role']
      frame = node['frame'] || {}
      puts "    #{'  ' * depth}#{uid || '(none)'} [#{role}] (#{frame['x']&.round},#{frame['y']&.round} #{frame['width']&.round}x#{frame['height']&.round}) - #{label}"
      (node['children'] || []).each { |child| print_element_tree(child, depth + 1) }
    end

    # Tap Add Source button - handles both empty state (body button) and non-empty state (toolbar button)
    def tap_add_source_button
      # Try the body button label first (works for empty state)
      begin
        @axe.tap_label('Add Source')
        return
      rescue UITest::Axe::AxeError
        # Not found - try toolbar button
      end

      # Try the toolbar + button by ID
      begin
        @axe.tap_id('sources.addButton')
        return
      rescue UITest::Axe::AxeError
        # Not found - try coordinates
      end

      # Fallback: tap the toolbar + button by coordinates (top-right area)
      # On iPhone 17 Pro (402pt width), the + button is in the nav bar at ~(370, 93)
      @axe.tap_coordinates(x: 370, y: 93)
    end

    # Navigate to the Remote Server form in the AddSourceView
    # The AddSourceView shows a list of source types
    def select_remote_server_tab
      @axe.tap_label('Add Remote Server')
      sleep 0.5
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
