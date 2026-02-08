# frozen_string_literal: true

module UITest
  # Helper for player interactions in UI tests.
  # Provides methods to wait for player states and control playback.
  class PlayerHelper
    def initialize(axe)
      @axe = axe
    end

    # Wait for player sheet to be expanded
    # @param timeout [Integer] Maximum time to wait in seconds
    def wait_for_player_expanded(timeout: 15)
      puts '  Waiting for player to expand...'
      start_time = Time.now

      loop do
        # Check for expanded player using accessibility label
        return true if @axe.text_visible?('player.expandedSheet')

        elapsed = Time.now - start_time
        if elapsed > timeout
          @axe.screenshot('debug_player_expand_timeout')
          raise "Player did not expand after #{timeout} seconds"
        end

        sleep 0.5
      end
    end

    # Wait for playback to start (player expanded means video is loading/playing)
    # @param timeout [Integer] Maximum time to wait in seconds
    def wait_for_playback_started(timeout: 20)
      puts '  Waiting for playback to start...'
      start_time = Time.now

      loop do
        # Player expanded sheet being visible indicates playback started
        # The specific controls may not be exposed in accessibility tree
        if @axe.text_visible?('player.expandedSheet')
          # Wait a bit more for video to actually start loading
          sleep 2.0
          puts "  Playback started after #{(Time.now - start_time).round(1)}s"
          return true
        end

        elapsed = Time.now - start_time
        if elapsed > timeout
          @axe.screenshot('debug_playback_start_timeout')
          raise "Playback did not start after #{timeout} seconds"
        end

        sleep 0.5
      end
    end

    # Tap Play button on video info sheet
    def tap_play_button
      puts '  Tapping Play button on video info...'
      # Play button is in the action bar below video thumbnail
      # Based on screenshot analysis: approximately (80, 400)
      @axe.tap_coordinates(x: 80, y: 400)
      sleep 0.5
    end

    # Close the player using the close button (X in bottom control bar)
    def close_player
      puts '  Closing player...'

      # Close button is the X on the right side of the bottom control bar
      # The control bar is a floating pill at the bottom
      # Based on earlier AXe tree, buttons are around y=806-808
      # The X button is the rightmost, at approximately x=350-360
      @axe.tap_coordinates(x: 355, y: 810)
      sleep 1
      puts '  Player closed'
    end

    # Check if player is expanded
    # @return [Boolean] true if player sheet is expanded
    def player_expanded?
      @axe.text_visible?('player.expandedSheet')
    end

    # Check if player is closed (not expanded)
    # @return [Boolean] true if player sheet is not visible
    def player_closed?
      !@axe.text_visible?('player.expandedSheet')
    end

    # Check if mini player is visible
    # @return [Boolean] true if mini player is visible
    def mini_player_visible?
      @axe.text_visible?('player.miniPlayer')
    end

    # Wait for player to be fully closed
    # @param timeout [Integer] Maximum time to wait in seconds
    def wait_for_player_closed(timeout: 10)
      puts '  Waiting for player to close...'
      start_time = Time.now

      loop do
        return true if player_closed?

        elapsed = Time.now - start_time
        if elapsed > timeout
          @axe.screenshot('debug_player_close_timeout')
          raise "Player did not close after #{timeout} seconds"
        end

        sleep 0.3
      end
    end

    private

    # Tap in the center of the screen to show player controls
    # Controls auto-hide after a few seconds, so we need to tap to reveal them
    def tap_to_show_controls
      # Tap in the center of the video area to show controls
      @axe.tap_coordinates(x: 200, y: 300)
      sleep 0.5
    end
  end
end
