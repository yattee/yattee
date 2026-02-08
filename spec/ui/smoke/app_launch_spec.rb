# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'App Launch', :smoke do
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

    # Initialize AXe
    @axe = UITest::Axe.new(@udid)
  end

  after(:all) do
    # Terminate app
    UITest::App.terminate(udid: @udid, silent: true) if @udid

    # Shutdown simulator unless --keep-simulator
    UITest::Simulator.shutdown(@udid) if @udid && !UITest::Config.keep_simulator?
  end

  describe 'Library tab' do
    it 'displays the Library navigation bar' do
      # With toolbarTitleDisplayMode(.inlineLarge), the title is an AXHeading with AXLabel "Library"
      # but no AXUniqueId, so we check for the text instead
      expect(@axe).to have_text('Library')
    end

    it 'displays the Tab Bar' do
      expect(@axe).to have_text('Tab Bar')
    end

    it 'displays the Playlists card' do
      expect(@axe).to have_element('library.card.playlists')
    end

    it 'displays the Bookmarks card' do
      expect(@axe).to have_element('library.card.bookmarks')
    end

    it 'displays the History card' do
      expect(@axe).to have_element('library.card.history')
    end

    it 'displays the Downloads card' do
      expect(@axe).to have_element('library.card.downloads')
    end

    it 'displays the Channels card' do
      expect(@axe).to have_element('library.card.channels')
    end

    it 'matches the baseline screenshot', :visual do
      screenshot = @axe.screenshot('app-launch-library')
      expect(screenshot).to match_baseline
    end
  end
end
