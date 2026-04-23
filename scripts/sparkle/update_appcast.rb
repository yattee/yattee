#!/usr/bin/env ruby
# frozen_string_literal: true

# Signs a Sparkle update .zip with the provided EdDSA private key and prepends
# a new <item> entry to the appcast.xml file. Creates the appcast from
# scripts/sparkle/appcast_template.xml if it does not yet exist.
#
# Usage:
#   update_appcast.rb \
#     --zip <path-to-Yattee-X.Y.Z-macOS.zip> \
#     --version 2.0.1 \
#     --build 260 \
#     --channel stable|beta \
#     --tag 2.0.1-260 \
#     --sign-update-bin <path-to-sign_update> \
#     --ed-key-file <path-to-ed-private-key-file> \
#     --appcast <path-to-appcast.xml> \
#     [--minimum-system-version 15.0] \
#     [--release-notes-url <url>]

require 'optparse'
require 'time'
require 'rexml/document'
require 'fileutils'
require 'open3'

options = {
  channel: 'stable',
  minimum_system_version: '15.0'
}

OptionParser.new do |opts|
  opts.on('--zip PATH') { |v| options[:zip] = v }
  opts.on('--version V') { |v| options[:version] = v }
  opts.on('--build B') { |v| options[:build] = v }
  opts.on('--channel NAME') { |v| options[:channel] = v }
  opts.on('--tag TAG') { |v| options[:tag] = v }
  opts.on('--sign-update-bin PATH') { |v| options[:sign_update_bin] = v }
  opts.on('--ed-key-file PATH') { |v| options[:ed_key_file] = v }
  opts.on('--appcast PATH') { |v| options[:appcast] = v }
  opts.on('--minimum-system-version V') { |v| options[:minimum_system_version] = v }
  opts.on('--release-notes-url URL') { |v| options[:release_notes_url] = v }
  opts.on('--repo OWNER/NAME') { |v| options[:repo] = v }
end.parse!

%i[zip version build tag sign_update_bin ed_key_file appcast repo].each do |k|
  raise "Missing required argument: --#{k.to_s.tr('_', '-')}" if options[k].nil? || options[k].empty?
end

raise "Zip not found: #{options[:zip]}" unless File.exist?(options[:zip])
raise "sign_update binary not found: #{options[:sign_update_bin]}" unless File.executable?(options[:sign_update_bin])
raise "Ed key file not found: #{options[:ed_key_file]}" unless File.exist?(options[:ed_key_file])

# ---- 1. Produce EdDSA signature via Sparkle's sign_update ----
#
# sign_update prints: sparkle:edSignature="..." length="..."
cmd = [options[:sign_update_bin], '--ed-key-file', options[:ed_key_file], options[:zip]]
puts "[appcast] signing: #{cmd.join(' ')}"
stdout, status = Open3.capture2(*cmd)
raise "sign_update failed (exit #{status.exitstatus}):\n#{stdout}" unless status.success?

sig_line = stdout.strip.lines.last.to_s.strip
ed_signature = sig_line[/edSignature="([^"]+)"/, 1]
length = sig_line[/length="([^"]+)"/, 1]
raise "Could not parse sign_update output: #{stdout.inspect}" if ed_signature.nil? || length.nil?

# ---- 2. Load (or seed) the appcast document ----
appcast_path = options[:appcast]
unless File.exist?(appcast_path)
  template = File.join(File.dirname(__FILE__), 'appcast_template.xml')
  FileUtils.mkdir_p(File.dirname(appcast_path))
  FileUtils.cp(template, appcast_path)
end

doc = REXML::Document.new(File.read(appcast_path))
doc.context[:attribute_quote] = :quote
channel = doc.root.elements['channel'] or raise 'appcast.xml missing <channel>'

# ---- 3. Remove any existing item for the same version+build (idempotent re-runs) ----
channel.elements.each('item') do |item|
  existing_build = item.elements['sparkle:version']&.text
  existing_version = item.elements['sparkle:shortVersionString']&.text
  if existing_build == options[:build].to_s && existing_version == options[:version]
    channel.delete_element(item)
  end
end

# ---- 4. Build the new <item> ----
zip_basename = File.basename(options[:zip])
download_url = "https://github.com/#{options[:repo]}/releases/download/#{options[:tag]}/#{zip_basename}"

item = REXML::Element.new('item')

title = REXML::Element.new('title')
title.text = "Version #{options[:version]} (#{options[:build]})"
item.add_element(title)

pubdate = REXML::Element.new('pubDate')
pubdate.text = Time.now.utc.rfc2822
item.add_element(pubdate)

sparkle_version = REXML::Element.new('sparkle:version')
sparkle_version.text = options[:build].to_s
item.add_element(sparkle_version)

short_version = REXML::Element.new('sparkle:shortVersionString')
short_version.text = options[:version]
item.add_element(short_version)

min_sys = REXML::Element.new('sparkle:minimumSystemVersion')
min_sys.text = options[:minimum_system_version]
item.add_element(min_sys)

# Channel tag only on non-stable items. Sparkle treats untagged items as stable.
if options[:channel] && !options[:channel].empty? && options[:channel] != 'stable'
  channel_el = REXML::Element.new('sparkle:channel')
  channel_el.text = options[:channel]
  item.add_element(channel_el)
end

if options[:release_notes_url]
  notes = REXML::Element.new('sparkle:releaseNotesLink')
  notes.text = options[:release_notes_url]
  item.add_element(notes)
end

enclosure = REXML::Element.new('enclosure')
enclosure.add_attribute('url', download_url)
enclosure.add_attribute('type', 'application/octet-stream')
enclosure.add_attribute('sparkle:edSignature', ed_signature)
enclosure.add_attribute('length', length)
item.add_element(enclosure)

# ---- 5. Prepend the new item (most recent first) ----
first_item = channel.elements['item']
if first_item
  channel.insert_before(first_item, item)
else
  channel.add_element(item)
end

# ---- 6. Write back, pretty-printed ----
formatter = REXML::Formatters::Pretty.new(2)
formatter.compact = true
File.open(appcast_path, 'w') do |f|
  f.write(%Q(<?xml version="1.0" encoding="utf-8"?>\n))
  formatter.write(doc.root, f)
  f.write("\n")
end

puts "[appcast] wrote #{appcast_path}"
puts "[appcast] item: version=#{options[:version]} build=#{options[:build]} channel=#{options[:channel]} length=#{length}"
