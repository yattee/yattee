# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'Invidious behind HTTP Basic Auth', :smoke do
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

    # Initialize AXe and InstanceSetup helper
    @axe = UITest::Axe.new(@udid)
    @instance_setup = UITest::InstanceSetup.new(@axe)
  end

  after(:all) do
    UITest::App.terminate(udid: @udid, silent: true) if @udid
    UITest::Simulator.shutdown(@udid) if @udid && !UITest::Config.keep_simulator?
  end

  # Each example must start from a clean Home view. If a previous example
  # left the app on the AddRemoteServer form (or any other sheet), dismiss it.
  before(:each) do
    @instance_setup.send(:dismiss_any_sheets)
    @instance_setup.send(:wait_for_home, timeout: 15)
  rescue StandardError => e
    warn "  before(:each) reset failed: #{e.message}"
  end

  # On failure, take a screenshot so we can see what state the simulator was in.
  after(:each) do |example|
    next unless example.exception

    safe_name = example.full_description.gsub(/\W+/, '_')[0, 80]
    begin
      path = @axe.screenshot("invidious-basic-auth-FAIL-#{safe_name}")
      warn "  Failure screenshot saved to: #{path}"
    rescue StandardError => e
      warn "  Failed to capture screenshot: #{e.message}"
    end
  end

  describe 'add flow with basic-auth-required detection' do
    it 'retries detection with credentials and adds the instance' do
      skip 'INVIDIOUS_BASIC_AUTH_USERNAME / _PASSWORD not set' unless UITest::Config.invidious_basic_auth_credentials?

      url  = UITest::Config.invidious_basic_auth_url
      host = UITest::Config.invidious_basic_auth_host

      expect(@axe).to have_text('Home')

      @instance_setup.remove_and_add_invidious_with_basic_auth(
        url,
        username: UITest::Config.invidious_basic_auth_username,
        password: UITest::Config.invidious_basic_auth_password
      )

      # Verify the instance is in Sources
      @axe.tap_id('home.settingsButton')
      sleep 1

      expect(@axe).to have_element('settings.view')

      @axe.tap_id('settings.row.sources')
      sleep 0.5

      expect(@axe).to have_text(host)

      begin
        @axe.tap_id('settings.doneButton')
      rescue StandardError
        nil
      end
      sleep 0.5
    end
  end

  describe 'detection without credentials surfaces basic-auth-required state' do
    it 'shows the Retry Detection button when the proxy returns 401' do
      url = UITest::Config.invidious_basic_auth_url

      @instance_setup.send(:navigate_to_sources)
      @instance_setup.send(:tap_add_source_button)
      sleep 0.8
      @instance_setup.send(:select_remote_server_tab)

      @instance_setup.send(:wait_for_element, 'addRemoteServer.urlField')
      @axe.tap_id('addRemoteServer.urlField')
      sleep 0.5
      @axe.type(url)
      sleep 0.5
      @axe.tap_id('addRemoteServer.detectButton')

      # Should land in the basicAuthRequired UI state, not the success path.
      @instance_setup.send(:wait_for_element, 'addRemoteServer.retryDetectionButton', timeout: 20)
      expect(@axe).to have_element('addRemoteServer.retryDetectionButton')
      expect(@axe).not_to have_element('addRemoteServer.detectedType')

      # Cancel and return Home so subsequent specs start clean.
      begin
        @axe.tap_label('Cancel')
      rescue StandardError
        @axe.swipe(start_x: 200, start_y: 300, end_x: 200, end_y: 700, duration: 0.3)
      end
      sleep 0.5
      @instance_setup.send(:close_settings)
    end
  end

  describe 'logging in to the proxied Invidious account' do
    it 'logs in via SID over the basic-auth channel' do
      skip 'Invidious basic-auth + proxied creds not set' unless
        UITest::Config.invidious_basic_auth_credentials? &&
        UITest::Config.invidious_proxied_credentials?

      url  = UITest::Config.invidious_basic_auth_url
      host = UITest::Config.invidious_basic_auth_host

      # Ensure the instance exists (idempotent — adds it if a previous spec hasn't already)
      unless @instance_setup.invidious_exists?(host)
        @instance_setup.add_invidious_with_basic_auth(
          url,
          username: UITest::Config.invidious_basic_auth_username,
          password: UITest::Config.invidious_basic_auth_password
        )
      end

      # login_invidious reads Config.invidious_email/_password (which themselves
      # read INVIDIOUS_EMAIL / INVIDIOUS_PASSWORD), so swap those env vars for the
      # duration of the call to use the proxied account credentials.
      with_env(
        'INVIDIOUS_EMAIL' => UITest::Config.invidious_proxied_email,
        'INVIDIOUS_PASSWORD' => UITest::Config.invidious_proxied_password
      ) do
        @instance_setup.login_invidious(host)
      end

      expect(@instance_setup.invidious_logged_in?(host)).to be true
    end
  end

  # Temporarily replace ENV vars for the duration of a block.
  def with_env(overrides)
    previous = overrides.to_h { |k, _| [k, ENV[k]] }
    overrides.each { |k, v| ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
