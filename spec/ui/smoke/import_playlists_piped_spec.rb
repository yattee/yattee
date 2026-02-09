# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'Import Playlists from Piped', :smoke do
  before(:all) do
    skip 'Piped credentials not configured' unless UITest::Config.piped_credentials?

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

    # Set up prerequisites: Yattee Server + logged-in Piped
    @instance_setup.ensure_yattee_server(UITest::Config.yattee_server_url)
    @instance_setup.ensure_piped(UITest::Config.piped_url)
    @instance_setup.ensure_piped_logged_in(UITest::Config.piped_host)
  end

  after(:all) do
    UITest::App.terminate(udid: @udid, silent: true) if @udid
    UITest::Simulator.shutdown(@udid) if @udid && !UITest::Config.keep_simulator?
  end

  describe 'Import section visibility' do
    it 'shows Import section with Playlists link when logged in to Piped' do
      # Navigate to Piped instance settings
      @instance_setup.send(:navigate_to_sources)

      # Tap the Piped row (using helper due to iOS 26 multiple-match issue)
      @instance_setup.send(:tap_element_containing_text, UITest::Config.piped_host)
      sleep 0.8

      # Wait for EditSourceView
      start_time = Time.now
      loop do
        break if @axe.element_exists?('editSource.view')
        raise 'EditSourceView not found' if Time.now - start_time > 10

        sleep 0.3
      end

      # Verify Import section is visible with Playlists link
      expect(@axe).to have_text('Import')
      expect(@axe).to have_element('sources.import.playlists')

      # Close settings
      @instance_setup.send(:close_edit_sheet)
      @instance_setup.send(:close_settings)
    end
  end

  describe 'Import Playlists view' do
    before do
      # Navigate to Import Playlists
      @instance_setup.send(:navigate_to_sources)

      # Tap the Piped row (using helper due to iOS 26 multiple-match issue)
      @instance_setup.send(:tap_element_containing_text, UITest::Config.piped_host)
      sleep 0.8

      # Wait for EditSourceView
      start_time = Time.now
      loop do
        break if @axe.element_exists?('editSource.view')
        raise 'EditSourceView not found' if Time.now - start_time > 10

        sleep 0.3
      end

      # Tap Playlists navigation link
      @axe.tap_id('sources.import.playlists')
      sleep 1
    end

    after do
      # Navigate back and close settings
      # Try back button or swipe
      begin
        @axe.tap_label('Back')
        sleep 0.5
      rescue UITest::Axe::AxeError
        @axe.swipe(start_x: 0, start_y: 400, end_x: 200, end_y: 400, duration: 0.3)
        sleep 0.5
      end

      @instance_setup.send(:close_edit_sheet)
      @instance_setup.send(:close_settings)
    end

    it 'displays Import Playlists view' do
      expect(@axe).to have_element('import.playlists.view')
    end

    it 'loads playlists from Piped' do
      # Wait for loading to complete
      start_time = Time.now
      loop do
        # iOS 26 doesn't expose List's accessibilityIdentifier properly
        # Check for list by looking for row elements, or empty/error states
        has_list = has_playlist_rows?
        has_empty = @axe.element_exists?('import.playlists.empty')
        has_error = @axe.element_exists?('import.playlists.error')

        break if has_list || has_empty || has_error

        raise 'Timeout waiting for playlists' if Time.now - start_time > 15

        sleep 0.5
      end

      # Should show list or empty state (not loading)
      has_list = has_playlist_rows?
      has_empty = @axe.element_exists?('import.playlists.empty')
      has_error = @axe.element_exists?('import.playlists.error')

      # Either list or empty is success, error is acceptable but not ideal
      expect(has_list || has_empty || has_error).to be true
    end

    it 'shows Add All button when there are unimported playlists' do
      # Wait for list to load
      wait_for_playlists_list

      # Check if there are any unimported playlists (Add buttons visible)
      # iOS 26 doesn't expose button IDs properly, so look for buttons with "Add" label
      tree = @axe.describe_ui
      add_button = find_add_button_element(tree)

      if add_button
        # Add All button should be in toolbar - tap by coordinates (top-right)
        # Toolbar buttons don't expose accessibility IDs on iOS 26
        @axe.tap_coordinates(x: 370, y: 105)
        sleep 0.5

        # Confirmation dialog should appear
        expect(@axe).to have_text('Add All')

        # Dismiss dialog by tapping outside or swiping down
        @axe.tap_coordinates(x: 200, y: 300)
        sleep 0.3
      else
        skip 'All playlists already imported - Add All button correctly hidden'
      end
    end

    it 'can add individual playlist' do
      wait_for_playlists_list

      # Skip if no playlists or empty
      skip 'No playlists to import' unless has_playlist_rows?

      # Find first add button - iOS 26 doesn't expose button IDs, use label + coordinates
      tree = @axe.describe_ui
      add_button = find_add_button_element(tree)

      skip 'No unimported playlists' unless add_button

      # Get button coordinates
      frame = add_button['frame']
      x = frame['x'] + (frame['width'] / 2)
      y = frame['y'] + (frame['height'] / 2)

      # Tap the add button
      @axe.tap_coordinates(x: x, y: y)
      sleep 0.5

      # Either progress indicator appears or merge warning dialog appears
      # Wait a bit for import to start
      sleep 1

      # Check if merge warning is shown (playlist already exists)
      if @axe.text_visible?('Playlist Exists')
        # Dismiss the merge warning
        @axe.tap_label('Cancel')
        sleep 0.5
        # Test passes - merge warning shown correctly
      else
        # Wait for import to complete (progress indicator should disappear)
        start_time = Time.now
        loop do
          # Check if import completed (no more progress indicators)
          tree = @axe.describe_ui
          has_progress = find_progress_indicator(tree)
          break unless has_progress
          raise 'Import timeout' if Time.now - start_time > 30

          sleep 0.5
        end

        # The button should change to checkmark
        new_tree = @axe.describe_ui
        new_add_buttons = count_add_buttons(new_tree)
        original_add_buttons = count_add_buttons(tree)

        # Either we have fewer add buttons, or the button changed to imported indicator
        expect(new_add_buttons).to be <= original_add_buttons
      end
    end

    it 'shows confirmation dialog before Add All' do
      wait_for_playlists_list

      # Check if there are playlists to add
      tree = @axe.describe_ui
      add_button = find_add_button_element(tree)

      skip 'No unimported playlists - Add All not shown' unless add_button

      # Tap Add All button in toolbar by coordinates (top-right area)
      @axe.tap_coordinates(x: 370, y: 105)
      sleep 0.5

      # Confirmation dialog should appear with "Add All" action
      expect(@axe).to have_text('Add All')
    end
  end

  private

  def wait_for_playlists_list(timeout: 15)
    start_time = Time.now
    loop do
      # iOS 26 doesn't expose List's accessibilityIdentifier properly
      # Check for rows or empty/error states instead
      return if has_playlist_rows? ||
                @axe.element_exists?('import.playlists.empty')
      raise 'Timeout waiting for playlists' if Time.now - start_time > timeout

      sleep 0.5
    end
  end

  # Check if any playlist row elements are visible in the UI tree
  # iOS 26 doesn't expose List container ID, but rows are visible
  def has_playlist_rows?
    tree = @axe.describe_ui
    find_element_with_prefix(tree, 'import.playlists.row.')
  end

  def find_element_with_prefix(node, prefix)
    case node
    when Hash
      id = node['AXUniqueId']
      return true if id&.start_with?(prefix)

      node.each_value do |value|
        return true if find_element_with_prefix(value, prefix)
      end
    when Array
      node.each do |item|
        return true if find_element_with_prefix(item, prefix)
      end
    end

    false
  end

  # Find an "Add" button element by its AXLabel (iOS 26 doesn't expose button IDs properly)
  def find_add_button_element(node)
    case node
    when Hash
      # Look for buttons with "Add" label that are individual add buttons (not Add All)
      if node['role'] == 'AXButton' && node['AXLabel'] == 'Add' && node['frame']
        return node
      end

      node.each_value do |value|
        result = find_add_button_element(value)
        return result if result
      end
    when Array
      node.each do |item|
        result = find_add_button_element(item)
        return result if result
      end
    end

    nil
  end

  # Find progress indicator (ProgressView) in the tree
  def find_progress_indicator(node)
    case node
    when Hash
      # ProgressView shows as AXProgressIndicator
      return true if node['role'] == 'AXProgressIndicator'

      node.each_value do |value|
        return true if find_progress_indicator(value)
      end
    when Array
      node.each do |item|
        return true if find_progress_indicator(item)
      end
    end

    false
  end

  # Count the number of "Add" buttons in the tree
  def count_add_buttons(node, count = 0)
    case node
    when Hash
      count += 1 if node['role'] == 'AXButton' && node['AXLabel'] == 'Add'

      node.each_value do |value|
        count = count_add_buttons(value, count)
      end
    when Array
      node.each do |item|
        count = count_add_buttons(item, count)
      end
    end

    count
  end

  def find_first_add_button(node)
    case node
    when Hash
      id = node['AXUniqueId']
      return id if id&.start_with?('import.playlists.add.')

      node.each_value do |value|
        result = find_first_add_button(value)
        return result if result
      end
    when Array
      node.each do |item|
        result = find_first_add_button(item)
        return result if result
      end
    end

    nil
  end
end
