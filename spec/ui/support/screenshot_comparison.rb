# frozen_string_literal: true

require 'open3'
require 'yaml'
require 'fileutils'

module UITest
  # Handles visual regression testing by comparing screenshots
  class ScreenshotComparison
    class DependencyError < StandardError; end

    attr_reader :current_path, :name

    def initialize(current_path)
      @current_path = current_path
      @name = File.basename(current_path, '.png')
    end

    # Check if ImageMagick is installed
    # @return [Boolean] true if ImageMagick compare command is available
    def self.imagemagick_available?
      @imagemagick_available ||= begin
        _output, status = Open3.capture2e('which', 'compare')
        status.success?
      end
    end

    # Raise an error if ImageMagick is not installed
    def self.require_imagemagick!
      return if imagemagick_available?

      raise DependencyError, <<~ERROR
        ImageMagick is required for visual regression testing but was not found.

        Install it with Homebrew:
          brew install imagemagick

        Or skip visual tests with:
          ./bin/ui-test --tag ~visual
      ERROR
    end

    # Path to baseline screenshot
    def baseline_path
      File.join(Config.baseline_dir, "#{@name}.png")
    end

    # Path to diff image
    def diff_path
      File.join(Config.diff_dir, "#{@name}_diff.png")
    end

    # Check if baseline exists and is valid
    def baseline_exists?
      valid_png?(baseline_path)
    end

    # Check if current screenshot exists and is valid
    def current_exists?
      valid_png?(@current_path)
    end

    # Validate that a file exists and is a valid PNG
    # @param path [String] Path to the file
    # @return [Boolean] true if file exists and has valid PNG header
    def valid_png?(path)
      return false unless File.exist?(path)
      return false unless File.size(path) > 8 # PNG header is 8 bytes minimum

      # Check PNG magic bytes: 89 50 4E 47 0D 0A 1A 0A
      File.open(path, 'rb') do |f|
        header = f.read(8)
        header&.bytes == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
      end
    rescue StandardError
      false
    end

    # Compare current screenshot to baseline
    # @param threshold [Float] Maximum allowed difference (0.0 to 1.0)
    # @return [Boolean] true if screenshots match within threshold
    def matches_baseline?(threshold: Config.default_diff_threshold)
      # If generating baseline, always "matches" (we'll save it)
      if Config.generate_baseline?
        update_baseline
        return true
      end

      # Validate current screenshot exists and is valid
      unless current_exists?
        puts "  Current screenshot invalid or missing: #{@current_path}"
        puts "  File exists: #{File.exist?(@current_path)}, size: #{File.exist?(@current_path) ? File.size(@current_path) : 'N/A'}"
        return false
      end

      # If no baseline exists, fail (unless generating)
      unless baseline_exists?
        puts "  No baseline found: #{baseline_path}"
        puts '  Run with --generate-baseline to create it'
        return false
      end

      # Ensure ImageMagick is available for comparison
      self.class.require_imagemagick!

      # Compare using ImageMagick
      diff = calculate_diff
      matches = diff <= threshold

      # Generate diff image if there's a mismatch
      generate_diff_image unless matches

      matches
    end

    # Calculate the difference percentage between current and baseline
    # @return [Float] Difference as a percentage (0.0 to 1.0)
    def diff_percentage
      @diff_percentage ||= calculate_diff
    end

    # Generate a visual diff image highlighting differences
    def generate_diff_image
      Config.ensure_directories!

      # Use ImageMagick compare to create a diff image
      # AE = Absolute Error count, fuzz allows small color variations
      _output, _status = Open3.capture2e(
        'compare', '-metric', 'AE', '-fuzz', '5%',
        '-highlight-color', 'red', '-lowlight-color', 'white',
        baseline_path, @current_path, diff_path
      )

      # compare returns exit code 1 if images differ, which is expected
      puts "  Diff image saved: #{diff_path}" if File.exist?(diff_path)
    end

    # Copy current screenshot to baseline
    def update_baseline
      Config.ensure_directories!
      FileUtils.cp(@current_path, baseline_path)
      puts "  Baseline updated: #{baseline_path}"
    end

    # Check if this screenshot is marked as a false positive
    # @return [Boolean] true if marked as false positive
    def false_positive?
      fps = load_false_positives
      fps.key?(@name)
    end

    # Get the reason for false positive
    # @return [String, nil] Reason or nil if not a false positive
    def false_positive_reason
      fps = load_false_positives
      fps.dig(@name, 'reason')
    end

    private

    def calculate_diff
      return 0.0 unless baseline_exists?

      # Validate current screenshot before comparison
      unless current_exists?
        puts "  Warning: Current screenshot invalid or empty: #{@current_path}"
        return 1.0
      end

      # Use ImageMagick compare with RMSE (Root Mean Square Error)
      # This gives us a normalized difference value
      output, status = Open3.capture2e(
        'compare', '-metric', 'RMSE',
        baseline_path, @current_path, 'null:'
      )

      # Output format: "12345 (0.123456)" or "12345 (9.95509e-05)" for scientific notation
      # We want the normalized value in parentheses
      match = output.match(/\(([\d.e+-]+)\)/i)

      unless match
        # ImageMagick compare returns exit code 1 for different images (normal)
        # but returns exit code 2 for errors - log these
        if status.exitstatus == 2 || output.include?('error')
          puts "  Warning: ImageMagick comparison failed: #{output.strip}"
        else
          puts "  Warning: Could not parse ImageMagick output: #{output.strip}"
        end
        return 1.0
      end

      match[1].to_f
    rescue StandardError => e
      puts "  Warning: Failed to compare screenshots: #{e.message}"
      1.0
    end

    def load_false_positives
      return {} unless File.exist?(Config.false_positives_file)

      YAML.load_file(Config.false_positives_file) || {}
    rescue StandardError
      {}
    end
  end
end
