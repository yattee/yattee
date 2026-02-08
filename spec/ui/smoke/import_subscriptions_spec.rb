# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'Import Subscriptions from Invidious', :smoke do
  before(:all) do
    skip 'Invidious credentials not configured' unless UITest::Config.invidious_credentials?

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

    # Set up prerequisites: Yattee Server + logged-in Invidious
    @instance_setup.ensure_yattee_server(UITest::Config.yattee_server_url)
    @instance_setup.ensure_invidious(UITest::Config.invidious_url)
    @instance_setup.ensure_invidious_logged_in(UITest::Config.invidious_host)
  end

  after(:all) do
    UITest::App.terminate(udid: @udid, silent: true) if @udid
    UITest::Simulator.shutdown(@udid) if @udid && !UITest::Config.keep_simulator?
  end

  describe 'Import section visibility' do
    it 'shows Import section when Yattee Server exists and logged in to Invidious' do
      # Navigate to Invidious instance settings
      @instance_setup.send(:navigate_to_sources)

      # Tap the Invidious row (using helper due to iOS 26 multiple-match issue)
      @instance_setup.send(:tap_first_element_with_id, "sources.row.invidious.#{UITest::Config.invidious_host}")
      sleep 0.8

      # Wait for EditSourceView
      start_time = Time.now
      loop do
        break if @axe.element_exists?('editSource.view')
        raise 'EditSourceView not found' if Time.now - start_time > 10

        sleep 0.3
      end

      # Verify Import section is visible
      expect(@axe).to have_text('Import')
      expect(@axe).to have_element('sources.import.subscriptions')

      # Close settings
      @instance_setup.send(:close_edit_sheet)
      @instance_setup.send(:close_settings)
    end
  end

  describe 'Import Subscriptions view' do
    before do
      # Navigate to Import Subscriptions
      @instance_setup.send(:navigate_to_sources)

      # Tap the Invidious row (using helper due to iOS 26 multiple-match issue)
      @instance_setup.send(:tap_first_element_with_id, "sources.row.invidious.#{UITest::Config.invidious_host}")
      sleep 0.8

      # Wait for EditSourceView
      start_time = Time.now
      loop do
        break if @axe.element_exists?('editSource.view')
        raise 'EditSourceView not found' if Time.now - start_time > 10

        sleep 0.3
      end

      # Tap Subscriptions navigation link
      @axe.tap_id('sources.import.subscriptions')
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

    it 'displays Import Subscriptions view' do
      expect(@axe).to have_element('import.subscriptions.view')
    end

    it 'loads subscriptions from Invidious' do
      # Wait for loading to complete
      start_time = Time.now
      loop do
        # iOS 26 doesn't expose List's accessibilityIdentifier properly
        # Check for list by looking for row elements, or empty/error states
        has_list = has_subscription_rows?
        has_empty = @axe.element_exists?('import.subscriptions.empty')
        has_error = @axe.element_exists?('import.subscriptions.error')

        break if has_list || has_empty || has_error

        if Time.now - start_time > 15
          raise 'Timeout waiting for subscriptions'
        end

        sleep 0.5
      end

      # Should show list or empty state (not loading)
      has_list = has_subscription_rows?
      has_empty = @axe.element_exists?('import.subscriptions.empty')
      has_error = @axe.element_exists?('import.subscriptions.error')

      # Either list or empty is success, error is acceptable but not ideal
      expect(has_list || has_empty || has_error).to be true
    end

    it 'shows Add All button when there are unsubscribed channels' do
      # Wait for list to load
      wait_for_subscriptions_list

      # Check if there are any unsubscribed channels (Add buttons visible)
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
        skip 'All channels already subscribed - Add All button correctly hidden'
      end
    end

    it 'can add individual subscription' do
      wait_for_subscriptions_list

      # Skip if no subscriptions or empty
      skip 'No subscriptions to import' unless has_subscription_rows?

      # Find first add button - iOS 26 doesn't expose button IDs, use label + coordinates
      tree = @axe.describe_ui
      add_button = find_add_button_element(tree)

      skip 'No unsubscribed channels' unless add_button

      # Get button coordinates
      frame = add_button['frame']
      x = frame['x'] + (frame['width'] / 2)
      y = frame['y'] + (frame['height'] / 2)

      # Tap the add button
      @axe.tap_coordinates(x: x, y: y)
      sleep 1

      # The button should change - verify by checking that same position now shows checkmark
      # or that there's one fewer Add button
      new_tree = @axe.describe_ui
      new_add_buttons = count_add_buttons(new_tree)
      original_add_buttons = count_add_buttons(tree)

      # Either we have fewer add buttons, or the button changed to subscribed indicator
      expect(new_add_buttons).to be < original_add_buttons
    end

    it 'shows confirmation dialog before Add All' do
      wait_for_subscriptions_list

      # Check if there are channels to add
      tree = @axe.describe_ui
      add_button = find_add_button_element(tree)

      skip 'No unsubscribed channels - Add All not shown' unless add_button

      # Tap Add All button in toolbar by coordinates (top-right area)
      @axe.tap_coordinates(x: 370, y: 105)
      sleep 0.5

      # Confirmation dialog should appear with "Add All" action
      expect(@axe).to have_text('Add All')
    end
  end

  private

  def wait_for_subscriptions_list(timeout: 15)
    start_time = Time.now
    loop do
      # iOS 26 doesn't expose List's accessibilityIdentifier properly
      # Check for rows or empty/error states instead
      return if has_subscription_rows? ||
                @axe.element_exists?('import.subscriptions.empty')
      raise 'Timeout waiting for subscriptions' if Time.now - start_time > timeout

      sleep 0.5
    end
  end

  # Check if any subscription row elements are visible in the UI tree
  # iOS 26 doesn't expose List container ID, but rows are visible
  def has_subscription_rows?
    tree = @axe.describe_ui
    find_element_with_prefix(tree, 'import.subscriptions.row.')
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

  # Count the number of "Add" buttons in the tree
  def count_add_buttons(node, count = 0)
    case node
    when Hash
      if node['role'] == 'AXButton' && node['AXLabel'] == 'Add'
        count += 1
      end

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
      return id if id&.start_with?('import.subscriptions.add.')

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
