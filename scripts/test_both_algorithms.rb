#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/canon"
require_relative "../lib/canon/diff_formatter"

# Test XML content
xml1 = <<~XML
  <root>
    <person>
      <name>Alice</name>
      <age>30</age>
    </person>
  </root>
XML

xml2 = <<~XML
  <root>
    <person>
      <name>Bob</name>
      <age>25</age>
    </person>
  </root>
XML

puts "=" * 80
puts "Testing :both algorithm option"
puts "=" * 80
puts

# Test with verbose: true and diff_algorithm: :both
result = Canon::Comparison.equivalent?(
  xml1,
  xml2,
  verbose: true,
  diff_algorithm: :both,
)

puts "Result class: #{result.class}"
puts "Result equivalent?: #{result.equivalent?}"
puts

# Create formatter
formatter = Canon::DiffFormatter.new(use_color: true)

# Format the comparison result
output = formatter.format_comparison_result(result, xml1, xml2)

puts output
