# frozen_string_literal: true

require 'rspec/expectations'

# Custom RSpec matchers for AXe-based UI testing
module UITest
  module Matchers
    # Matcher to check if an element with accessibility identifier exists
    #
    # Usage:
    #   expect(axe).to have_element("tab.library")
    #
    RSpec::Matchers.define :have_element do |identifier|
      match do |axe|
        axe.element_exists?(identifier)
      end

      failure_message do |_axe|
        "expected to find element with accessibility identifier '#{identifier}' but it was not found"
      end

      failure_message_when_negated do |_axe|
        "expected not to find element with accessibility identifier '#{identifier}' but it was found"
      end

      description do
        "have element with accessibility identifier '#{identifier}'"
      end
    end

    # Matcher to check if text is visible in the accessibility tree
    #
    # Usage:
    #   expect(axe).to have_text("Library")
    #
    RSpec::Matchers.define :have_text do |text|
      match do |axe|
        axe.text_visible?(text)
      end

      failure_message do |_axe|
        "expected to find text '#{text}' but it was not visible"
      end

      failure_message_when_negated do |_axe|
        "expected not to find text '#{text}' but it was visible"
      end

      description do
        "have visible text '#{text}'"
      end
    end

    # Matcher to compare screenshot to baseline
    #
    # Usage:
    #   expect(screenshot_path).to match_baseline
    #   expect(screenshot_path).to match_baseline(threshold: 0.02)
    #
    RSpec::Matchers.define :match_baseline do |threshold: UITest::Config.default_diff_threshold|
      match do |screenshot_path|
        @comparison = UITest::ScreenshotComparison.new(screenshot_path)

        # If it's a known false positive, consider it a match
        return true if @comparison.false_positive?

        @comparison.matches_baseline?(threshold: threshold)
      end

      failure_message do |screenshot_path|
        @comparison ||= UITest::ScreenshotComparison.new(screenshot_path)

        msg = "screenshot '#{@comparison.name}' differs from baseline"
        msg += " by #{(@comparison.diff_percentage * 100).round(2)}%"
        msg += " (threshold: #{(threshold * 100).round(2)}%)"
        msg += "\n  Baseline: #{@comparison.baseline_path}"
        msg += "\n  Current:  #{screenshot_path}"
        msg += "\n  Diff:     #{@comparison.diff_path}" if File.exist?(@comparison.diff_path)
        msg
      end

      failure_message_when_negated do |_screenshot_path|
        'expected screenshot not to match baseline but it did'
      end

      description do
        "match baseline screenshot within #{(threshold * 100).round(2)}% threshold"
      end
    end
  end
end
