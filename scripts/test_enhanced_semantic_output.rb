#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "canon"

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
puts "Testing Enhanced Semantic Tree Diff Output"
puts "=" * 80
puts

# Test with semantic diff algorithm
result = Canon::Comparison.equivalent?(
  xml1,
  xml2,
  diff_algorithm: :semantic,
  verbose: true,
)

puts "Algorithm: #{result.algorithm}"
puts "Equivalent: #{result.equivalent?}"
puts "Number of differences: #{result.differences.length}"
puts
puts "Detailed Operations:"
puts "-" * 80

result.differences.each_with_index do |diff, i|
  puts "\n#{i + 1}. #{diff.dimension.to_s.upcase}"
  puts "   Reason: #{diff.reason}"

  # Access the underlying operation metadata
  if diff.respond_to?(:node1) && diff.node1
    puts "   Node1: #{diff.node1.inspect}"
  end

  if diff.respond_to?(:node2) && diff.node2
    puts "   Node2: #{diff.node2.inspect}"
  end

  # Show metadata if available
  if diff.respond_to?(:metadata)
    puts "   Metadata: #{diff.metadata.inspect}"
  end
end

puts
puts "=" * 80
puts "Testing operation metadata directly"
puts "=" * 80

# Access tree diff operations directly
if result.respond_to?(:match_options) && result.match_options
  ops = result.match_options[:tree_diff_operations]

  if ops
    puts "\nDirect Tree Diff Operations:"
    puts "-" * 80

    ops.each_with_index do |op, i|
      puts "\n#{i + 1}. Operation: #{op.type.to_s.upcase}"

      # Show path information
      if op[:path]
        puts "   Path: #{op[:path]}"
      end

      if op[:old_path] && op[:new_path]
        puts "   Old Path: #{op[:old_path]}"
        puts "   New Path: #{op[:new_path]}"
      end

      # Show content information
      if op[:content]
        puts "   Content: #{op[:content]}"
      end

      if op[:old_content] && op[:new_content]
        puts "   Old Content: #{op[:old_content]}"
        puts "   New Content: #{op[:new_content]}"
      end

      # Show changes detail
      if op[:changes]
        puts "   Changes:"
        op[:changes].each do |key, change|
          puts "     - #{key}: #{change[:old]} => #{change[:new]}"
        end
      end
    end
  else
    puts "No tree_diff_operations found in match_options"
  end
else
  puts "No match_options available"
end

puts
puts "=" * 80
puts "Test Complete"
puts "=" * 80
