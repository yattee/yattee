# frozen_string_literal: true

require 'open3'
require 'json'

module UITest
  # Manages iOS Simulator lifecycle
  class Simulator
    class SimulatorError < StandardError; end

    class << self
      # Boot a simulator by device name and return its UDID
      # @param device_name [String] Name of the device (e.g., "iPhone 17 Pro")
      # @return [String] UDID of the booted simulator
      def boot(device_name)
        udid = find_udid(device_name)
        raise SimulatorError, "Simulator '#{device_name}' not found" unless udid

        status = device_status(udid)

        if status == 'Shutdown'
          puts "Booting simulator '#{device_name}'..."
          run_simctl('boot', udid)
          wait_until_booted(udid)
        elsif status == 'Booted'
          puts "Simulator '#{device_name}' is already booted"
        else
          puts "Simulator '#{device_name}' is in state '#{status}', waiting..."
          wait_until_booted(udid)
        end

        # Set consistent status bar for reproducible screenshots
        set_status_bar_overrides(udid)

        udid
      end

      # Shutdown a simulator by UDID
      # @param udid [String] UDID of the simulator
      def shutdown(udid)
        return unless udid

        status = device_status(udid)
        return if status == 'Shutdown'

        clear_status_bar_overrides(udid)
        puts 'Shutting down simulator...'
        run_simctl('shutdown', udid)
      end

      # Set status bar overrides for consistent screenshots
      # Uses Apple's iconic 9:41 time and full signal/battery
      # @param udid [String] UDID of the simulator
      def set_status_bar_overrides(udid)
        puts 'Setting status bar overrides for consistent screenshots...'
        run_simctl(
          'status_bar', udid, 'override',
          '--time', '9:41',
          '--batteryState', 'charged',
          '--batteryLevel', '100',
          '--wifiBars', '3',
          '--cellularBars', '4'
        )
      end

      # Clear status bar overrides
      # @param udid [String] UDID of the simulator
      def clear_status_bar_overrides(udid)
        run_simctl('status_bar', udid, 'clear')
      rescue SimulatorError
        # Ignore errors when clearing (simulator may already be shut down)
        nil
      end

      # Find UDID for a device by name
      # @param device_name [String] Name of the device
      # @return [String, nil] UDID or nil if not found
      def find_udid(device_name)
        output, status = Open3.capture2('xcrun', 'simctl', 'list', 'devices', 'available', '-j')
        raise SimulatorError, 'Failed to list simulators' unless status.success?

        data = JSON.parse(output)
        devices = data['devices'].values.flatten

        # Find exact match first
        device = devices.find { |d| d['name'] == device_name }
        device&.fetch('udid', nil)
      end

      # Get device status by UDID
      # @param udid [String] UDID of the simulator
      # @return [String] Status (e.g., "Booted", "Shutdown")
      def device_status(udid)
        output, status = Open3.capture2('xcrun', 'simctl', 'list', 'devices', '-j')
        raise SimulatorError, 'Failed to get device status' unless status.success?

        data = JSON.parse(output)
        devices = data['devices'].values.flatten

        device = devices.find { |d| d['udid'] == udid }
        device&.fetch('state', 'Unknown') || 'Unknown'
      end

      # Wait until simulator is fully booted
      # @param udid [String] UDID of the simulator
      # @param timeout [Integer] Timeout in seconds
      def wait_until_booted(udid, timeout: 60)
        start_time = Time.now

        loop do
          status = device_status(udid)
          return if status == 'Booted'

          if Time.now - start_time > timeout
            raise SimulatorError, "Timeout waiting for simulator to boot (status: #{status})"
          end

          sleep 1
        end
      end

      private

      def run_simctl(*args)
        output, status = Open3.capture2e('xcrun', 'simctl', *args)
        raise SimulatorError, "simctl #{args.first} failed: #{output}" unless status.success?

        output
      end
    end
  end
end
