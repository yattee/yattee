# frozen_string_literal: true

module UITest
  # Configuration for UI tests
  class Config
    class << self
      # Device name for simulator (from env or default)
      def device
        ENV.fetch('UI_TEST_DEVICE', 'iPhone 17 Pro')
      end

      # Sanitized device name for file paths (replaces spaces and special chars)
      def device_slug
        device.gsub(/[^a-zA-Z0-9]/, '_')
      end

      # iOS version of the selected simulator
      def ios_version
        @ios_version ||= detect_ios_version
      end

      # Sanitized iOS version for file paths (e.g., "18_1")
      def ios_version_slug
        ios_version.gsub('.', '_')
      end

      # Combined device and iOS version slug for snapshot directories
      def snapshot_slug
        "#{device_slug}/iOS_#{ios_version_slug}"
      end

      private

      # Detect iOS version from the simulator runtime
      def detect_ios_version
        require 'json'
        output = `xcrun simctl list devices available -j 2>/dev/null`
        data = JSON.parse(output)

        # Find the device and extract iOS version from runtime key
        data['devices'].each do |runtime, devices|
          next unless runtime.include?('iOS')

          devices.each do |dev|
            next unless dev['name'] == device

            # Runtime format: "com.apple.CoreSimulator.SimRuntime.iOS-18-1"
            match = runtime.match(/iOS[.-](\d+)[.-](\d+)/)
            return "#{match[1]}.#{match[2]}" if match
          end
        end

        'unknown'
      rescue StandardError
        'unknown'
      end

      public

      # App bundle identifier
      def bundle_id
        'stream.yattee.app'
      end

      # Yattee Server URL for testing (configurable via env)
      def yattee_server_url
        ENV.fetch('YATTEE_SERVER_URL', 'https://yp.home.arekf.net')
      end

      # Extract host from Yattee Server URL for identifier matching
      def yattee_server_host
        URI.parse(yattee_server_url).host
      end

      # Yattee Server username for testing (configurable via env)
      def yattee_server_username
        ENV.fetch('YATTEE_SERVER_USERNAME', nil)
      end

      # Yattee Server password for testing (configurable via env)
      def yattee_server_password
        ENV.fetch('YATTEE_SERVER_PASSWORD', nil)
      end

      # Whether Yattee Server credentials are configured
      def yattee_server_credentials?
        yattee_server_username && yattee_server_password
      end

      # Invidious URL for testing (configurable via env)
      def invidious_url
        ENV.fetch('INVIDIOUS_URL', 'https://invidious.home.arekf.net')
      end

      # Extract host from Invidious URL for identifier matching
      def invidious_host
        URI.parse(invidious_url).host
      end

      # Invidious account email for testing (configurable via env)
      def invidious_email
        ENV.fetch('INVIDIOUS_EMAIL', nil)
      end

      # Invidious account password for testing (configurable via env)
      def invidious_password
        ENV.fetch('INVIDIOUS_PASSWORD', nil)
      end

      # Whether Invidious credentials are configured
      def invidious_credentials?
        invidious_email && invidious_password
      end

      # Piped URL for testing (configurable via env)
      def piped_url
        ENV.fetch('PIPED_URL', 'https://pipedapi.home.arekf.net')
      end

      # Extract host from Piped URL for identifier matching
      def piped_host
        URI.parse(piped_url).host
      end

      # Piped account username for testing (configurable via env)
      def piped_username
        ENV.fetch('PIPED_USERNAME', nil)
      end

      # Piped account password for testing (configurable via env)
      def piped_password
        ENV.fetch('PIPED_PASSWORD', nil)
      end

      # Whether Piped credentials are configured
      def piped_credentials?
        piped_username && piped_password
      end

      # Xcode project path (parent of spec directory)
      def project_path
        File.expand_path('..', spec_root)
      end

      # Xcode project file
      def xcodeproj
        File.join(project_path, 'Yattee.xcodeproj')
      end

      # Scheme to build
      def scheme
        'Yattee'
      end

      # Build configuration
      def configuration
        'Debug'
      end

      # Derived data path for builds
      def derived_data_path
        File.join(project_path, 'build')
      end

      # Path to built app
      def app_path
        File.join(derived_data_path, 'Build', 'Products', 'Debug-iphonesimulator', 'Yattee.app')
      end

      # Spec root directory
      def spec_root
        File.expand_path('../..', __dir__)
      end

      # Snapshots directory
      def snapshots_root
        File.join(spec_root, 'ui_snapshots')
      end

      # Baseline screenshots directory (device and iOS version specific)
      def baseline_dir
        File.join(snapshots_root, 'baseline', snapshot_slug)
      end

      # Current test run screenshots directory (device and iOS version specific)
      def current_dir
        File.join(snapshots_root, 'current', snapshot_slug)
      end

      # Diff images directory (device and iOS version specific)
      def diff_dir
        File.join(snapshots_root, 'diff', snapshot_slug)
      end

      # False positives YAML file
      def false_positives_file
        File.join(snapshots_root, 'false_positives.yml')
      end

      # Default threshold for visual comparison (1% difference allowed)
      def default_diff_threshold
        0.01
      end

      # Whether to generate baseline screenshots
      def generate_baseline?
        ENV['GENERATE_BASELINE'] == '1'
      end

      # Whether to skip building the app
      def skip_build?
        ENV['SKIP_BUILD'] == '1'
      end

      # Whether to keep simulator running after tests
      def keep_simulator?
        ENV['KEEP_SIMULATOR'] == '1'
      end

      # Whether to keep app data between runs (skip uninstall)
      def keep_app_data?
        ENV['KEEP_APP_DATA'] == '1'
      end

      # Timeout for waiting for elements (seconds)
      def element_timeout
        10
      end

      # Time to wait for app to stabilize after launch (seconds)
      def app_launch_wait
        3
      end

      # Ensure directories exist
      def ensure_directories!
        [baseline_dir, current_dir, diff_dir].each do |dir|
          FileUtils.mkdir_p(dir)
        end
      end
    end
  end
end
