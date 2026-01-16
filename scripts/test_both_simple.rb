#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/canon"

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
puts "Testing :both algorithm option (simple test)"
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
puts "DOM result class: #{result.dom_result.class}"
puts "DOM result equivalent?: #{result.dom_result.equivalent?}"
puts "DOM result algorithm: #{result.dom_result.algorithm}"
puts "DOM differences count: #{result.dom_result.differences.count}"
puts
puts "Tree result class: #{result.tree_result.class}"
puts "Tree result equivalent?: #{result.tree_result.equivalent?}"
puts "Tree result algorithm: #{result.tree_result.algorithm}"
puts "Tree differences count: #{result.tree_result.differences.count}"
puts "Tree operations count: #{result.tree_result.operations.count}"
