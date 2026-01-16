#!/usr/bin/env ruby
# frozen_string_literal: true

# Investigation script to check if Canon is properly classifying
# differences as normative vs informative according to match options

require "bundler/setup"
require_relative "../lib/canon"

# Sample tests from the 43 common failures
SAMPLE_TESTS = [
  { file: "blocks_notes_spec.rb", line: 494, desc: "blocks with notes" },
  { file: "blocks_provisions_spec.rb", line: 4, desc: "block provisions" },
  { file: "cleanup_spec.rb", line: 180, desc: "cleanup processing" },
  { file: "figures_spec.rb", line: 5, desc: "figure handling" },
  { file: "tables_spec.rb", line: 4, desc: "table structure" },
].freeze

def run_single_test(test_info)
  puts "\n#{'=' * 80}"
  puts "Test: #{test_info[:file]}:#{test_info[:line]}"
  puts "Description: #{test_info[:desc]}"
  puts "=" * 80

  # Run the test with both algorithms to capture output
  isodoc_path = File.expand_path("~/src/mn/isodoc")
  test_path = File.join(isodoc_path, "spec/isodoc", test_info[:file])

  unless File.exist?(test_path)
    puts "⚠️  Test file not found: #{test_path}"
    return
  end

  %w[dom semantic].each do |algorithm|
    puts "\n--- #{algorithm.upcase} Algorithm ---"

    # Run test and capture output
    cmd = "cd #{isodoc_path} && " \
          "CANON_DIFF_ALGORITHM=#{algorithm} " \
          "bundle exec rspec #{test_path}:#{test_info[:line]} 2>&1"

    output = `#{cmd}`

    # Check if test passed or failed
    if output.include?("0 failures")
      puts "✅ PASSED"
      next
    elsif output.include?("1 failure")
      puts "❌ FAILED"
    else
      puts "⚠️  Unexpected output"
      next
    end

    # Extract diff information
    extract_diff_info(output)
  end
end

def extract_diff_info(output)
  # Look for dimension information in the output
  dimensions_found = []

  # Common patterns in Canon output
  dimension_patterns = [
    /DIFFERENCE.*dimension:\s*(\w+)/i,
    /Dimension:\s*(\w+)/i,
    /\[(\w+)\]/,
  ]

  dimension_patterns.each do |pattern|
    output.scan(pattern) do |match|
      dimension = match[0].downcase.to_sym
      dimensions_found << dimension unless dimensions_found.include?(dimension)
    end
  end

  if dimensions_found.any?
    puts "\n📊 Dimensions detected:"
    dimensions_found.each do |dim|
      puts "   - #{dim}"
    end
  else
    puts "\n⚠️  No dimension information found in output"
  end

  # Look for normative/informative classification
  if output.match?(/normative/i)
    puts "\n📝 Normative differences found"
  end
  if output.match?(/informative/i)
    puts "\n📝 Informative differences found"
  end

  # Count differences
  diff_count = output.scan(/DIFFERENCE|difference/i).length
  puts "\n📈 Approximate difference count: #{diff_count}"
end

def check_match_options_config
  puts "\n#{'=' * 80}"
  puts "Match Options Configuration Check"
  puts "=" * 80

  # Check HTML match options (most common format in isodoc tests)
  puts "\nHTML Default Match Options:"

  html_defaults = Canon::Comparison::MatchOptions::Xml::FORMAT_DEFAULTS[:html]
  html_defaults.each do |dimension, behavior|
    normative = behavior != :ignore
    status = normative ? "NORMATIVE" : "INFORMATIVE"
    puts "  #{dimension.to_s.ljust(25)} : #{behavior.to_s.ljust(12)} → #{status}"
  end

  puts "\nKey classifications:"
  puts "  - attribute_order: #{html_defaults[:attribute_order]} " \
       "→ #{html_defaults[:attribute_order] == :ignore ? 'INFORMATIVE ✓' : 'NORMATIVE ✗'}"
  puts "  - text_content: #{html_defaults[:text_content]} " \
       "→ NORMATIVE (but normalized during matching)"
  puts "  - structural_whitespace: #{html_defaults[:structural_whitespace]} " \
       "→ NORMATIVE (but normalized during matching)"
  puts "  - comments: #{html_defaults[:comments]} " \
       "→ #{html_defaults[:comments] == :ignore ? 'INFORMATIVE ✓' : 'NORMATIVE ✗'}"
end

def main
  puts "Canon Classification Investigation"
  puts "Checking if differences are properly classified as normative vs informative"
  puts "based on match options in effect"

  # First, show the match options configuration
  check_match_options_config

  # Then run sample tests
  puts "\n\nRunning sample tests to examine actual behavior..."
  SAMPLE_TESTS.each do |test_info|
    run_single_test(test_info)
  end

  puts "\n#{'=' * 80}"
  puts "Investigation complete"
  puts "=" * 80
  puts "\nKey Questions:"
  puts "1. Are both algorithms reporting the same dimensions?"
  puts "2. Are dimensions correctly classified per match options?"
  puts "3. Are ignored dimensions being treated as informative?"
  puts "4. Are normalized dimensions still showing as normative when they differ?"
end

main if __FILE__ == $PROGRAM_NAME
