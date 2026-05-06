# frozen_string_literal: true

require_relative '../spec_helper'

# Regression test for the "session is a required parameter" Piped auth bug
# (introduced in build 259 by commit aed78c13f, which moved the auth token from
# the `Authorization` header to a `?authToken=` query parameter on endpoints
# that the Piped backend only accepts via the header).
#
# Reproduces by adding a Piped instance, logging in, then exercising the two
# settings flows that hit the broken endpoints directly:
#   - Import Subscriptions       → /subscriptions
#   - Import Playlists           → /user/playlists
#
# When the bug is present, the Piped backend returns
# `{"error":"session is a required parameter"}` and the import view surfaces
# either an explicit error element or that exact text in the AX tree. This spec
# fails (red) on a buggy build and passes (green) once the API client sends the
# token via the Authorization header.
RSpec.describe 'Piped Login Endpoints', :smoke do
  before(:all) do
    skip 'Piped credentials not configured' unless UITest::Config.piped_credentials?

    @udid = UITest::Simulator.boot(UITest::Config.device)

    UITest::App.build(
      device: UITest::Config.device,
      skip: UITest::Config.skip_build?
    )

    UITest::App.install(udid: @udid)
    UITest::App.launch(udid: @udid)

    sleep UITest::Config.app_launch_wait

    @axe = UITest::Axe.new(@udid)
    @instance_setup = UITest::InstanceSetup.new(@axe)

    @instance_setup.ensure_piped(UITest::Config.piped_url)
    @instance_setup.ensure_piped_logged_in(UITest::Config.piped_host)
  end

  after(:all) do
    UITest::App.terminate(udid: @udid, silent: true) if @udid
    UITest::Simulator.shutdown(@udid) if @udid && !UITest::Config.keep_simulator?
  end

  describe 'authenticated endpoints do not return "session is a required parameter"' do
    it 'loads Import Subscriptions without the session error' do
      open_import_view('sources.import.subscriptions')

      result, last_tree = wait_for_import_settled(prefix: 'import.subscriptions')
      safe_screenshot('piped-login-import-subscriptions')

      expect(UITest::Axe.label_in_tree?(last_tree, 'session is a required parameter')).to(
        be(false),
        'Piped /subscriptions returned "session is a required parameter" — ' \
        'auth token is being sent in the wrong place (query param instead of Authorization header).'
      )
      expect(%i[list empty]).to include(result),
                       "Expected /subscriptions to return list or empty state, got #{result.inspect}."
    ensure
      close_import_view
    end

    it 'loads Import Playlists without the session error' do
      open_import_view('sources.import.playlists')

      result, last_tree = wait_for_import_settled(prefix: 'import.playlists')
      safe_screenshot('piped-login-import-playlists')

      expect(UITest::Axe.label_in_tree?(last_tree, 'session is a required parameter')).to(
        be(false),
        'Piped /user/playlists returned "session is a required parameter" — ' \
        'auth token is being sent in the wrong place (query param instead of Authorization header).'
      )
      expect(%i[list empty]).to include(result),
                       "Expected /user/playlists to return list or empty state, got #{result.inspect}."
    ensure
      close_import_view
    end
  end

  private

  # Navigate Settings → Sources → Piped row → tap given import navigation link.
  def open_import_view(import_link_id)
    return_to_home

    @instance_setup.send(:navigate_to_sources)
    @instance_setup.send(:tap_element_containing_text, UITest::Config.piped_host)
    sleep 0.8

    start_time = Time.now
    loop do
      break if @axe.element_exists?('editSource.view')
      raise 'EditSourceView not found' if Time.now - start_time > 10

      sleep 0.3
    end

    @axe.tap_id(import_link_id)
    sleep 1
  end

  # Get back to the Home tab. Tries gentle recovery first; as a last resort,
  # terminates and re-launches the app (login state survives in keychain/UserDefaults).
  def return_to_home(timeout: 15)
    # Give the app a moment to settle after the previous navigation.
    sleep 1.0
    return if on_home?

    start = Time.now
    loop do
      return if on_home?

      attempt_gentle_dismissals
      return if on_home?

      if Time.now - start > timeout
        warn '[piped_login_spec] Could not reach Home gently — relaunching app'
        safe_screenshot('debug-stuck-not-home')
        UITest::App.terminate(udid: @udid, silent: true)
        sleep 0.5
        UITest::App.launch(udid: @udid)
        sleep UITest::Config.app_launch_wait
        return if on_home?

        raise "Could not return to Home even after relaunch (#{timeout}s elapsed)"
      end

      sleep 0.5
    end
  end

  def on_home?
    @axe.text_visible?('Home') || @axe.element_exists?('home.settingsButton')
  rescue UITest::Axe::AxeError
    false
  end

  def attempt_gentle_dismissals
    # Try labels for sheets/nav back, but DO NOT swipe down from the top —
    # an iOS swipe-down from the upper screen pulls down Spotlight and ejects us
    # from the app.
    %w[Cancel Done Back].each do |label|
      begin
        @axe.tap_label(label)
        sleep 0.4
        return if on_home?
      rescue UITest::Axe::AxeError
        next
      end
    end

    begin
      @axe.tap_id('settings.doneButton')
      sleep 0.4
    rescue UITest::Axe::AxeError
      # ignore
    end
  end

  # Wait for the import view to settle. Each iteration fetches the AX tree once
  # and runs all checks against it locally — that's ~6× fewer `axe` subprocess
  # spawns than calling element_exists? / text_visible? per check. Returns
  # `[state, tree]` where state is :list / :empty / :error / :unknown. iOS 26
  # doesn't reliably propagate the AXUniqueId from ContentUnavailableView, so
  # empty/error states are also detected by their visible localized titles.
  def wait_for_import_settled(prefix:, timeout: 25)
    empty_titles = {
      'import.subscriptions' => 'No Subscriptions',
      'import.playlists'     => 'No Playlists'
    }
    empty_title = empty_titles.fetch(prefix)

    start_time = Time.now
    last_tree = nil
    loop do
      tree = @axe.describe_ui rescue nil
      last_tree = tree if tree

      if tree
        return [:list, tree] if UITest::Axe.id_with_prefix_in_tree?(tree, "#{prefix}.row.")
        if UITest::Axe.id_in_tree?(tree, "#{prefix}.empty") || UITest::Axe.label_in_tree?(tree, empty_title)
          return [:empty, tree]
        end
        if UITest::Axe.id_in_tree?(tree, "#{prefix}.error") ||
           UITest::Axe.label_in_tree?(tree, 'session is a required parameter') ||
           UITest::Axe.label_in_tree?(tree, 'Failed to load')
          return [:error, tree]
        end
      end

      break if Time.now - start_time > timeout

      sleep 0.5
    end
    [:unknown, last_tree || {}]
  end

  def close_import_view
    begin
      @axe.tap_label('Back')
      sleep 0.5
    rescue UITest::Axe::AxeError
      @axe.swipe(start_x: 0, start_y: 400, end_x: 200, end_y: 400, duration: 0.3)
      sleep 0.5
    end

    begin
      @instance_setup.send(:close_edit_sheet)
      @instance_setup.send(:close_settings)
    rescue StandardError
      nil
    end
  end

  def safe_screenshot(name)
    @axe.screenshot(name)
  rescue UITest::Axe::AxeError => e
    warn "  screenshot '#{name}' failed: #{e.message}"
  end
end
