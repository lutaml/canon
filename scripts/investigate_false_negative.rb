#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "canon"
require "nokogiri"

# Test one of the false negative cases
# These are passing semantic but failing DOM

# Test case: Check if the space insertion is causing problems
def test_space_insertion_edge_cases
  puts "=" * 80
  puts "Testing Space Insertion Edge Cases"
  puts "=" * 80

  # Case 1: Elements without any child elements should not get spaces
  xml1 = "<root><text>Hello World</text></root>"
  xml2 = "<root><text>Hello  World</text></root>"

  puts "\nCase 1: Simple text (no child elements)"
  puts "  XML1: #{xml1}"
  puts "  XML2: #{xml2}"

  doc1 = Nokogiri::XML(xml1)
  doc2 = Nokogiri::XML(xml2)

  adapter = Canon::TreeDiff::Adapters::XMLAdapter.new
  tree1 = adapter.to_tree(doc1)
  tree2 = adapter.to_tree(doc2)

  text_node1 = tree1.children.first
  text_node2 = tree2.children.first

  puts "  Tree1 text value: #{text_node1.value.inspect}"
  puts "  Tree2 text value: #{text_node2.value.inspect}"
  puts "  Should be different: #{text_node1.value != text_node2.value}"

  # Case 2: Mixed content WITH br
  xml3 = "<root><text>A<br/>B</text></root>"
  xml4 = "<root><text>A<br/>C</text></root>"

  puts "\nCase 2: Mixed content with <br/>"
  puts "  XML3: #{xml3}"
  puts "  XML4: #{xml4}"

  doc3 = Nokogiri::XML(xml3)
  doc4 = Nokogiri::XML(xml4)

  tree3 = adapter.to_tree(doc3)
  tree4 = adapter.to_tree(doc4)

  text_node3 = tree3.children.first
  text_node4 = tree4.children.first

  puts "  Tree3 text value: #{text_node3.value.inspect}"
  puts "  Tree4 text value: #{text_node4.value.inspect}"
  puts "  Should be different: #{text_node3.value != text_node4.value}"

  # Case 3: Text nodes that are just whitespace between elements
  xml5 = "<root><a>X</a> <b>Y</b></root>"
  xml6 = "<root><a>X</a><b>Y</b></root>"

  puts "\nCase 3: Whitespace between elements"
  puts "  XML5: #{xml5}"
  puts "  XML6: #{xml6}"

  doc5 = Nokogiri::XML(xml5)
  doc6 = Nokogiri::XML(xml6)

  tree5 = adapter.to_tree(doc5)
  tree6 = adapter.to_tree(doc6)

  puts "  Tree5 root value: #{tree5.value.inspect}"
  puts "  Tree6 root value: #{tree6.value.inspect}"
  puts "  Tree5 root has #{tree5.children.size} children"
  puts "  Tree6 root has #{tree6.children.size} children"
end

test_space_insertion_edge_cases
