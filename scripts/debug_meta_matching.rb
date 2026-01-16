#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "canon"

# Test case: Meta element with attributes should match
expected = <<~HTML
  <html>
    <head>
      <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    </head>
    <body>
      <p>Test</p>
    </body>
  </html>
HTML

actual = <<~HTML
  <html>
    <head>
      <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    </head>
    <body>
      <p>Test</p>
    </body>
  </html>
HTML

puts "=" * 80
puts "Testing Meta Element Matching"
puts "=" * 80

result = Canon::Comparison.equivalent?(expected, actual,
                                       format: :html4,
                                       diff_algorithm: :semantic,
                                       verbose: true)

if result.is_a?(Canon::Comparison::ComparisonResult)
  puts "\nResult: #{result.equivalent? ? 'PASS ✅' : 'FAIL ❌'}"
  puts "Normative diffs: #{result.normative_differences.count}"
  puts "Total diffs: #{result.differences.count}"

  unless result.equivalent?
    puts "\nDifferences:"
    result.differences.each_with_index do |diff, i|
      puts "\n  #{i + 1}. #{diff.inspect}"
    end
  end
else
  puts "Result: #{result}"
end
