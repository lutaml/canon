#!/usr/bin/env ruby
# frozen_string_literal: true

# Test a single false positive case to understand the pattern
# Usage: ruby scripts/test_single_false_positive.rb

require "bundler/setup"
require "canon"

# Based on MIXED_CONTENT_FIX_RESULTS.md, one false positive is in sourcecode_spec.rb:124
# Let's test a simple sourcecode case with whitespace

# This represents a typical sourcecode/pre element case
expected = <<~HTML
  <div class="example">
    <pre class="sourcecode" id="X">
      Line 1
      Line 2
    </pre>
  </div>
HTML

actual = <<~HTML
    <div class="example">
      <pre class="sourcecode" id="X">Line 1
  Line 2</pre>
    </div>
HTML

puts "=" * 80
puts "TEST: Sourcecode whitespace handling (False Positive Pattern)"
puts "=" * 80

# Test DOM algorithm
puts "\n1. DOM ALGORITHM (Baseline):"
puts "-" * 40
dom_result = Canon::Comparison.equivalent?(expected, actual,
                                           format: :html,
                                           diff_algorithm: :dom,
                                           verbose: false)
puts "Result: #{dom_result ? '✅ PASS (no difference)' : '❌ FAIL (has difference)'}"

# Test Semantic algorithm
puts "\n2. SEMANTIC ALGORITHM (Under Test):"
puts "-" * 40
semantic_result = Canon::Comparison.equivalent?(expected, actual,
                                                format: :html,
                                                diff_algorithm: :semantic,
                                                verbose: false)
puts "Result: #{semantic_result ? '✅ PASS (no difference)' : '❌ FAIL (has difference)'}"

# Analysis
puts "\n#{'=' * 80}"
if dom_result && !semantic_result
  puts "❌ FALSE POSITIVE DETECTED"
  puts "   DOM says: equivalent"
  puts "   Semantic says: different"
  puts "\nThis is the pattern we need to fix!"

  # Get detailed diff
  puts "\nDetailed semantic diff:"
  Canon::Comparison.equivalent?(expected, actual,
                                format: :html,
                                diff_algorithm: :semantic,
                                verbose: true)
elsif !dom_result && semantic_result
  puts "❌ FALSE NEGATIVE DETECTED"
  puts "   DOM says: different"
  puts "   Semantic says: equivalent"
elsif dom_result && semantic_result
  puts "✅ BOTH AGREE: No difference (correct match)"
else
  puts "✅ BOTH AGREE: Has difference (correct non-match)"
end

# Now test with a metadata element case
puts "\n\n#{'=' * 80}"
puts "TEST: Metadata element handling (Another False Positive Pattern)"
puts "=" * 80

expected2 = <<~HTML
  <p id="X">
    <span class="fmt-xref-label">Clause 1</span>
    <a name="X">Content here</a>
  </p>
HTML

actual2 = <<~HTML
  <p id="X">
    <span class="fmt-xref-label">Clause 1</span>
    <bookmark id="X"/>
    Content here
  </p>
HTML

puts "\n1. DOM ALGORITHM:"
dom2 = Canon::Comparison.equivalent?(expected2, actual2,
                                     format: :html,
                                     diff_algorithm: :dom,
                                     verbose: false)
puts "Result: #{dom2 ? '✅ PASS' : '❌ FAIL'}"

puts "\n2. SEMANTIC ALGORITHM:"
semantic2 = Canon::Comparison.equivalent?(expected2, actual2,
                                          format: :html,
                                          diff_algorithm: :semantic,
                                          verbose: false)
puts "Result: #{semantic2 ? '✅ PASS' : '❌ FAIL'}"

puts "\n#{'=' * 80}"
if dom2 && !semantic2
  puts "❌ FALSE POSITIVE in metadata handling"
elsif !dom2 && semantic2
  puts "❌ FALSE NEGATIVE in metadata handling"
elsif dom2 && semantic2
  puts "✅ BOTH AGREE: equivalent"
else
  puts "✅ BOTH AGREE: different"
end
