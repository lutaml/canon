#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "canon"
require "canon/diff_formatter"

# Test XML with differences
xml1 = <<~XML
  <root>
    <section id="1">
      <title>First Section</title>
      <paragraph>Original text</paragraph>
    </section>
    <section id="2">
      <title>Second Section</title>
    </section>
  </root>
XML

xml2 = <<~XML
  <root>
    <section id="1">
      <title>First Section Modified</title>
      <paragraph>Changed text</paragraph>
    </section>
    <section id="3">
      <title>Third Section</title>
    </section>
  </root>
XML

puts "=" * 80
puts "Testing Semantic Tree Diff vs DOM Diff"
puts "=" * 80
puts

# Test with show_compare enabled
puts "Running with show_compare=true (verbose mode)..."
puts "-" * 80

result = Canon::Comparison.equivalent?(
  xml1,
  xml2,
  verbose: true,
  show_compare: true,
)

if result.is_a?(Canon::Comparison::CombinedComparisonResult)
  puts "\n✓ Got CombinedComparisonResult"
  puts "  Decision Algorithm: #{result.decision_algorithm}"
  puts "  Equivalent? #{result.equivalent?}"
  puts

  puts "DOM Diff Algorithm:"
  puts "-" * 40
  dom_result = result.dom_result
  if dom_result.respond_to?(:differences)
    puts "  Number of differences: #{dom_result.differences.length}"
    dom_result.differences.first(3).each_with_index do |diff, i|
      puts "  #{i + 1}. #{diff.inspect[0..200]}"
    end
  else
    puts "  Result: #{dom_result.inspect[0..200]}"
  end
  puts

  puts "Tree Diff Algorithm:"
  puts "-" * 40
  tree_result = result.tree_result
  if tree_result.respond_to?(:differences)
    puts "  Number of differences: #{tree_result.differences.length}"
    tree_result.differences.first(3).each_with_index do |diff, i|
      puts "  #{i + 1}. #{diff.inspect[0..200]}"
    end
  else
    puts "  Result: #{tree_result.inspect[0..200]}"
  end
  puts

  # Test formatting
  puts "Formatted Output:"
  puts "-" * 40
  begin
    formatted = Canon::DiffFormatter.format(result, mode: :by_line)
    puts formatted[0..500]
  rescue StandardError => e
    puts "  Error formatting: #{e.message}"
    puts "  #{e.backtrace.first(3).join("\n  ")}"
  end
else
  puts "✗ Did not get CombinedComparisonResult, got: #{result.class}"
  puts "  Result: #{result.inspect[0..200]}"
end

puts
puts "=" * 80
puts "Test Complete"
puts "=" * 80
