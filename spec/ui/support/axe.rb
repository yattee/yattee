# frozen_string_literal: true

require 'open3'
require 'json'
require 'fileutils'

module UITest
  # Wrapper for AXe CLI tool for iOS Simulator automation
  class Axe
    class AxeError < StandardError; end

    attr_reader :udid

    def initialize(udid)
      @udid = udid
    end

    # Get the full accessibility UI tree as parsed JSON
    # @return [Hash] Parsed accessibility tree
    def describe_ui
      output, status = run_axe('describe-ui')
      raise AxeError, "describe-ui failed: #{output}" unless status.success?

      JSON.parse(output)
    rescue JSON::ParserError => e
      raise AxeError, "Failed to parse accessibility tree: #{e.message}"
    end

    # Check if an element with the given accessibility identifier exists
    # @param identifier [String] Accessibility identifier to find
    # @return [Boolean] true if element exists
    def element_exists?(identifier)
      tree = describe_ui
      find_element_in_tree(tree, identifier: identifier).present?
    rescue AxeError
      false
    end

    # Find an element by accessibility identifier
    # @param identifier [String] Accessibility identifier
    # @return [Hash, nil] Element data or nil if not found
    def find_element(identifier)
      tree = describe_ui
      find_element_in_tree(tree, identifier: identifier)
    end

    # Check if text is visible anywhere in the accessibility tree
    # @param text [String] Text to search for
    # @return [Boolean] true if text is visible
    def text_visible?(text)
      tree = describe_ui
      find_element_in_tree(tree, label: text).present?
    rescue AxeError
      false
    end

    # Tap on an element by accessibility identifier
    # @param identifier [String] Accessibility identifier
    def tap_id(identifier)
      output, status = run_axe('tap', '--id', identifier)
      raise AxeError, "tap failed: #{output}" unless status.success?
    end

    # Tap on an element by accessibility label
    # @param label [String] Accessibility label
    def tap_label(label)
      output, status = run_axe('tap', '--label', label)
      raise AxeError, "tap failed: #{output}" unless status.success?
    end

    # Tap at specific coordinates
    # @param x [Integer] X coordinate
    # @param y [Integer] Y coordinate
    def tap_coordinates(x:, y:)
      output, status = run_axe('tap', '-x', x.to_s, '-y', y.to_s)
      raise AxeError, "tap failed: #{output}" unless status.success?
    end

    # Perform a swipe gesture
    # @param start_x [Integer] Starting X coordinate
    # @param start_y [Integer] Starting Y coordinate
    # @param end_x [Integer] Ending X coordinate
    # @param end_y [Integer] Ending Y coordinate
    # @param duration [Float] Duration in seconds (optional)
    def swipe(start_x:, start_y:, end_x:, end_y:, duration: nil)
      args = ['swipe', '--start-x', start_x.to_s, '--start-y', start_y.to_s,
              '--end-x', end_x.to_s, '--end-y', end_y.to_s]
      args += ['--duration', duration.to_s] if duration

      output, status = run_axe(*args)
      raise AxeError, "swipe failed: #{output}" unless status.success?
    end

    # Perform a preset gesture
    # @param preset [String] Gesture preset (scroll-up, scroll-down, etc.)
    def gesture(preset)
      output, status = run_axe('gesture', preset)
      raise AxeError, "gesture failed: #{output}" unless status.success?
    end

    # Type text
    # @param text [String] Text to type
    def type(text)
      output, status = Open3.capture2e('axe', 'type', '--stdin', '--udid', @udid, stdin_data: text)
      raise AxeError, "type failed: #{output}" unless status.success?
    end

    # Press the home button
    def home_button
      output, status = run_axe('button', 'home')
      raise AxeError, "home button failed: #{output}" unless status.success?
    end

    # Press a key by keycode
    # @param keycode [Integer] HID keycode (e.g., 40 for Return/Enter)
    def press_key(keycode)
      output, status = run_axe('key', keycode.to_s)
      raise AxeError, "key press failed: #{output}" unless status.success?
    end

    # Press Return/Enter key
    def press_return
      press_key(40)
    end

    # Press Escape key
    def press_escape
      press_key(41)
    end

    # Take a screenshot and save it
    # @param name [String] Screenshot name (without extension)
    # @return [String] Path to the saved screenshot
    def screenshot(name)
      Config.ensure_directories!

      path = File.join(Config.current_dir, "#{name}.png")
      output, status = run_axe('screenshot', '--output', path)
      raise AxeError, "screenshot failed: #{output}" unless status.success?

      # Wait for file to be fully written to disk
      wait_for_file(path)

      path
    end

    private

    def run_axe(*)
      Open3.capture2e('axe', *, '--udid', @udid)
    end

    # Wait for a file to exist and have non-zero size
    # Helps avoid race conditions where screenshot isn't fully written
    # @param path [String] Path to the file
    # @param timeout [Float] Maximum time to wait in seconds
    def wait_for_file(path, timeout: 2.0)
      start_time = Time.now
      loop do
        return if File.exist?(path) && File.size(path) > 100

        break if Time.now - start_time > timeout

        sleep 0.1
      end
    end

    # Recursively search the accessibility tree for an element
    # @param node [Hash, Array] Current node in the tree
    # @param identifier [String, nil] Accessibility identifier to match (AXUniqueId)
    # @param label [String, nil] Accessibility label to match (AXLabel)
    # @return [Hash, nil] Found element or nil
    def find_element_in_tree(node, identifier: nil, label: nil)
      case node
      when Hash
        # Check if this node matches by identifier (AXUniqueId in AXe output)
        return node if identifier && node['AXUniqueId'] == identifier

        # Check if this node matches by label (AXLabel in AXe output)
        return node if label && node['AXLabel']&.include?(label)

        # Recursively search children
        node.each_value do |value|
          result = find_element_in_tree(value, identifier: identifier, label: label)
          return result if result
        end
      when Array
        node.each do |item|
          result = find_element_in_tree(item, identifier: identifier, label: label)
          return result if result
        end
      end

      nil
    end
  end
end

# Add present? method for nil/empty checking
class Object
  def present?
    respond_to?(:empty?) ? !empty? : !nil?
  end
end

class NilClass
  def present?
    false
  end
end
