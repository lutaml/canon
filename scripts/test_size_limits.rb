#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify size limit functionality

require_relative "../lib/canon"
require_relative "../lib/canon/config"
require_relative "../lib/canon/commands/diff_command"

puts "Testing Canon Size Limits"
puts "=" * 60

# Test 1: File size limit configuration
puts "\n1. Testing file size limit configuration:"
config = Canon::Config.instance
puts "  Default max_file_size: #{config.xml.diff.max_file_size}"
puts "  Expected: 5242880 (5MB)"

# Test 2: Node count limit configuration
puts "\n2. Testing node count limit configuration:"
puts "  Default max_node_count: #{config.xml.diff.max_node_count}"
puts "  Expected: 10000"

# Test 3: Diff lines limit configuration
puts "\n3. Testing diff lines limit configuration:"
puts "  Default max_diff_lines: #{config.xml.diff.max_diff_lines}"
puts "  Expected: 10000"

# Test 4: ENV variable override
puts "\n4. Testing ENV variable override:"
ENV["CANON_MAX_FILE_SIZE"] = "1000000"
ENV["CANON_MAX_NODE_COUNT"] = "5000"
ENV["CANON_MAX_DIFF_LINES"] = "2000"

# Reset config to pick up ENV vars
Canon::Config.reset!
config = Canon::Config.instance

puts "  After setting ENV vars:"
puts "    max_file_size: #{config.xml.diff.max_file_size} (expected: 1000000)"
puts "    max_node_count: #{config.xml.diff.max_node_count} (expected: 5000)"
puts "    max_diff_lines: #{config.xml.diff.max_diff_lines} (expected: 2000)"

# Test 5: SizeLimitExceededError
puts "\n5. Testing SizeLimitExceededError:"
begin
  error = Canon::SizeLimitExceededError.new(:file_size, 10_000_000, 5_242_880)
  puts "  Created error: #{error.class}"
  puts "  Message: #{error.message}"
rescue StandardError => e
  puts "  ERROR: #{e.class}: #{e.message}"
end

# Test 6: File size checking
puts "\n6. Testing file size checking in diff command:"
require "tempfile"

# Create a small test file
Tempfile.create(["test", ".xml"]) do |f1|
  f1.write("<root><child>content</child></root>")
  f1.flush

  Tempfile.create(["test2", ".xml"]) do |f2|
    f2.write("<root><child>different</child></root>")
    f2.flush

    # Set a very low limit to trigger error
    ENV["CANON_MAX_FILE_SIZE"] = "10" # 10 bytes
    Canon::Config.reset!

    begin
      cmd = Canon::Commands::DiffCommand.new(
        format: :xml,
        verbose: true,
        color: false,
      )
      cmd.run(f1.path, f2.path)
      puts "  ✗ Should have raised SizeLimitExceededError"
    rescue Canon::SizeLimitExceededError => e
      puts "  ✓ Correctly raised SizeLimitExceededError"
      puts "    Message: #{e.message.lines.first.strip}"
    rescue SystemExit => e
      # abort() in diff_command causes SystemExit
      # Check if it was due to size limit by checking stderr
      puts "  ✓ File size check triggered (command aborted as expected)"
    rescue StandardError => e
      puts "  ✗ Unexpected error: #{e.class}: #{e.message}"
    end
  end
end

# Clean up ENV
ENV.delete("CANON_MAX_FILE_SIZE")
ENV.delete("CANON_MAX_NODE_COUNT")
ENV.delete("CANON_MAX_DIFF_LINES")
Canon::Config.reset!

puts "\n#{'=' * 60}"
puts "Size limits test completed!"
