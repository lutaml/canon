#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to investigate false positives in semantic tree algorithm
# Usage: ruby scripts/investigate_false_positive.rb

require "bundler/setup"
require "canon"

# Simple test case demonstrating whitespace in sourcecode
expected = <<~XML
  <div>
    <pre class="sourcecode">
      Hey
      Que?
    </pre>
  </div>
XML

actual = <<~XML
    <div>
      <pre class="sourcecode">Hey
  Que?</pre>
    </div>
XML

puts "=" * 80
puts "Testing Whitespace Handling in <pre> Elements"
puts "=" * 80

# Test with DOM diff algorithm
puts "\n1. DOM DIFF ALGORITHM:"
puts "-" * 80
result_dom = Canon::Comparison.equivalent?(expected, actual,
                                           format: :html,
                                           diff_algorithm: :dom,
                                           verbose: true)

dom_match = result_dom.is_a?(Canon::Comparison::ComparisonResult) ? result_dom.equivalent? : result_dom
puts "Match: #{dom_match}"
if result_dom.is_a?(Canon::Comparison::ComparisonResult)
  puts "Normative diffs: #{result_dom.normative_differences.count}"
  puts "Total diffs: #{result_dom.differences.count}"
end

# Test with Semantic Tree diff algorithm
puts "\n2. SEMANTIC TREE ALGORITHM:"
puts "-" * 80
result_semantic = Canon::Comparison.equivalent?(expected, actual,
                                                format: :html,
                                                diff_algorithm: :semantic,
                                                verbose: true)

semantic_match = result_semantic.is_a?(Canon::Comparison::ComparisonResult) ? result_semantic.equivalent? : result_semantic
puts "Match: #{semantic_match}"
if result_semantic.is_a?(Canon::Comparison::ComparisonResult)
  puts "Normative diffs: #{result_semantic.normative_differences.count}"
  puts "Total diffs: #{result_semantic.differences.count}"
end

puts "\n#{'=' * 80}"
puts "ANALYSIS:"
puts "=" * 80

if dom_match && !semantic_match
  puts "❌ FALSE POSITIVE: Semantic tree incorrectly reports difference"

  if result_semantic.is_a?(Canon::Comparison::ComparisonResult)
    puts "\nDifferences found by semantic tree:"
    result_semantic.differences.each_with_index do |diff, i|
      puts "\n  Diff #{i + 1}:"
      puts "    Type: #{diff.class}"
      puts "    Normative: #{diff.normative?}" if diff.respond_to?(:normative?)
      puts "    Details: #{diff.inspect}"
    end
  end
elsif !dom_match && semantic_match
  puts "❌ FALSE NEGATIVE: Semantic tree misses real difference"
elsif dom_match && semantic_match
  puts "✅ BOTH AGREE: No difference (correct)"
else
  puts "✅ BOTH AGREE: Difference exists (correct)"
end
