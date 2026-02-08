# frozen_string_literal: true

require 'open3'

module UITest
  # Manages app build, install, and launch lifecycle
  class App
    class AppError < StandardError; end

    class << self
      # Build the app for simulator
      # @param device [String] Device name for destination
      # @param skip [Boolean] Skip build if true
      def build(device:, skip: false)
        if skip
          puts 'Skipping build (--skip-build)'
          validate_app_exists!
          return
        end

        puts "Building Yattee for #{device}..."

        args = [
          'xcodebuild',
          '-project', Config.xcodeproj,
          '-scheme', Config.scheme,
          '-configuration', Config.configuration,
          '-destination', "platform=iOS Simulator,name=#{device}",
          '-derivedDataPath', Config.derived_data_path,
          'build'
        ]

        # Run build and capture output
        output, status = Open3.capture2e(*args)

        unless status.success?
          # Extract relevant error lines
          error_lines = output.lines.select { |l| l.include?('error:') }.join
          raise AppError, "Build failed:\n#{error_lines.empty? ? output.last(2000) : error_lines}"
        end

        puts 'Build succeeded'
        validate_app_exists!
      end

      # Install app to simulator
      # @param udid [String] UDID of the simulator
      # By default, uninstalls first to reset app data (use --keep-app-data to skip)
      def install(udid:)
        validate_app_exists!

        # Uninstall first to reset app data (unless --keep-app-data)
        unless Config.keep_app_data?
          puts 'Resetting app data (uninstalling previous install)...'
          uninstall(udid: udid)

          # Reset keychain to prevent "Save Password?" dialogs during tests
          puts 'Resetting simulator keychain...'
          reset_keychain(udid: udid)
        end

        puts 'Installing app...'
        output, status = Open3.capture2e('xcrun', 'simctl', 'install', udid, Config.app_path)

        raise AppError, "Install failed: #{output}" unless status.success?

        puts 'App installed'
      end

      # Launch app on simulator
      # @param udid [String] UDID of the simulator
      def launch(udid:)
        puts 'Launching app...'

        # Terminate if already running
        terminate(udid: udid, silent: true)

        output, status = Open3.capture2e('xcrun', 'simctl', 'launch', udid, Config.bundle_id)

        raise AppError, "Launch failed: #{output}" unless status.success?

        puts 'App launched'
      end

      # Terminate app on simulator
      # @param udid [String] UDID of the simulator
      # @param silent [Boolean] Don't raise error if app not running
      def terminate(udid:, silent: false)
        output, status = Open3.capture2e('xcrun', 'simctl', 'terminate', udid, Config.bundle_id)

        # simctl terminate returns non-zero if app isn't running
        return if silent

        raise AppError, "Terminate failed: #{output}" unless status.success?
      end

      # Uninstall app from simulator
      # @param udid [String] UDID of the simulator
      def uninstall(udid:)
        Open3.capture2e('xcrun', 'simctl', 'uninstall', udid, Config.bundle_id)
        # Ignore errors - app might not be installed
      end

      # Reset simulator keychain to prevent "Save Password?" dialogs
      # @param udid [String] UDID of the simulator
      def reset_keychain(udid:)
        Open3.capture2e('xcrun', 'simctl', 'keychain', udid, 'reset')
        # Ignore errors - reset is best effort
      end

      private

      def validate_app_exists!
        return if File.exist?(Config.app_path)

        raise AppError, "App not found at #{Config.app_path}. Run build first or remove --skip-build"
      end
    end
  end
end
