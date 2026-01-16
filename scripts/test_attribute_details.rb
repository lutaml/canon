#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/canon"
require_relative "../lib/canon/diff_formatter"
require_relative "../lib/canon/diff_formatter/diff_detail_formatter"

# Test attribute values formatting - same attributes, different values
html1 = '<table id="T1" class="MsoNormalTable" border="1"></table>'
html2 = '<table id="T2" class="MsoNormalTable" border="2"></table>'

puts "=" * 70
puts "TEST 1: Multiple Attribute Values Differ (id removed, border changed)"
puts "=" * 70

result = Canon::Comparison.equivalent?(
  html1,
  html2,
  match_algorithm: :semantic_tree,
  ignore_attr_order: true,
  verbose: true,
)

# Print semantic diff report
if result.differences.any?
  report = Canon::DiffFormatter::DiffDetailFormatter.format_report(
    result.differences,
    use_color: true,
  )
  puts report
else
  puts "No differences found!"
end

puts "\n\n"
puts "=" * 70
puts "TEST 2: Attribute Order Differs"
puts "=" * 70

# Test attribute order formatting
html3 = '<table id="T1" class="MsoNormalTable" border="1"></table>'
html4 = '<table border="1" class="MsoNormalTable" id="T1"></table>'

result2 = Canon::Comparison.equivalent?(
  html3,
  html4,
  match_algorithm: :semantic_tree,
  ignore_attr_order: false, # Don't ignore order, so we see the difference
  verbose: true,
)

# Print semantic diff report
if result2.differences.any?
  report2 = Canon::DiffFormatter::DiffDetailFormatter.format_report(
    result2.differences,
    use_color: true,
  )
  puts report2
else
  puts "No differences found!"
end
