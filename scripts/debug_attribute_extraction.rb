#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/canon"
require_relative "../lib/canon/diff_formatter"
require_relative "../lib/canon/diff_formatter/diff_detail_formatter"

# Test attribute values formatting
html1 = '<table id="T1" class="MsoNormalTable" border="1"></table>'
html2 = '<table id="T2" class="MsoNormalTable" border="2"></table>'

result = Canon::Comparison.equivalent?(
  html1,
  html2,
  match_algorithm: :semantic_tree,
  ignore_attr_order: true,
  verbose: true,
)

puts "Number of differences: #{result.differences.length}"
puts

result.differences.each_with_index do |diff, i|
  puts "=" * 70
  puts "Difference ##{i + 1}"
  puts "=" * 70
  puts "Class: #{diff.class}"
  puts "Dimension: #{diff.dimension if diff.respond_to?(:dimension)}"

  if diff.respond_to?(:node1) && diff.respond_to?(:node2)
    node1 = diff.node1
    node2 = diff.node2

    puts "\nNode1:"
    puts "  Class: #{node1.class}"
    puts "  Name: #{node1.name if node1.respond_to?(:name)}"
    if node1.respond_to?(:attributes)
      puts "  Attributes: #{node1.attributes.inspect}"
      puts "  Attributes class: #{node1.attributes.class}"
      puts "  Attributes keys: #{node1.attributes.keys.inspect}"
      node1.attributes.each do |key, val|
        puts "    #{key.inspect} (#{key.class}) => #{val.inspect} (#{val.class})"
        if val.respond_to?(:value)
          puts "      val.value = #{val.value.inspect}"
        end
      end
    end

    puts "\nNode2:"
    puts "  Class: #{node2.class}"
    puts "  Name: #{node2.name if node2.respond_to?(:name)}"
    if node2.respond_to?(:attributes)
      puts "  Attributes: #{node2.attributes.inspect}"
      puts "  Attributes class: #{node2.attributes.class}"
      puts "  Attributes keys: #{node2.attributes.keys.inspect}"
      node2.attributes.each do |key, val|
        puts "    #{key.inspect} (#{key.class}) => #{val.inspect} (#{val.class})"
        if val.respond_to?(:value)
          puts "      val.value = #{val.value.inspect}"
        end
      end
    end
  end

  puts
end
