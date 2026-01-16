#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "canon"
require "nokogiri"

# Read the test files
expected_file = "/Users/mulgogi/src/mn/isodoc/spec/fixtures/html/isodoc-section-names-expected.html"
actual_file = "/Users/mulgogi/src/mn/isodoc/spec/fixtures/html/isodoc-section-names-actual.html"

expected = File.read(expected_file)
actual = File.read(actual_file)

puts "=" * 80
puts "ANALYZING <p> ELEMENT MATCHING"
puts "=" * 80

# Parse with Nokogiri to see what we have
doc1 = Nokogiri::HTML4(expected)
doc2 = Nokogiri::HTML4(actual)

# Find all <p> elements
p_elements1 = doc1.css("p")
p_elements2 = doc2.css("p")

puts "\nFile 1 has #{p_elements1.size} <p> elements"
puts "File 2 has #{p_elements2.size} <p> elements"

# Group by class attribute
p_by_class1 = p_elements1.group_by { |p| p["class"] }
p_by_class2 = p_elements2.group_by { |p| p["class"] }

puts "\nFile 1 <p> elements by class:"
p_by_class1.each do |klass, elements|
  puts "  #{klass.inspect}: #{elements.size} elements"
  elements.first(3).each do |el|
    content = el.text.strip
    content = "#{content[0..50]}..." if content.length > 50
    puts "    - #{content.inspect}"
  end
end

puts "\nFile 2 <p> elements by class:"
p_by_class2.each do |klass, elements|
  puts "  #{klass.inspect}: #{elements.size} elements"
  elements.first(3).each do |el|
    content = el.text.strip
    content = "#{content[0..50]}..." if content.length > 50
    puts "    - #{content.inspect}"
  end
end

# Now run Canon's tree diff to see what happens
puts "\n#{'=' * 80}"
puts "RUNNING CANON TREE DIFF"
puts "=" * 80

require_relative "../lib/canon/tree_diff/adapters/html_adapter"
require_relative "../lib/canon/tree_diff/matchers/hash_matcher"
require_relative "../lib/canon/tree_diff/matchers/similarity_matcher"
require_relative "../lib/canon/tree_diff/operations/operation_detector"

# Create trees
adapter = Canon::TreeDiff::Adapters::HtmlAdapter.new
tree1 = adapter.parse(expected)
tree2 = adapter.parse(actual)

puts "\nTree 1 has #{tree1.descendants.size} total nodes"
puts "Tree 2 has #{tree2.descendants.size} total nodes"

# Find <p> nodes in tree
p_nodes1 = tree1.descendants.select { |n| n.label == "p" }
p_nodes2 = tree2.descendants.select { |n| n.label == "p" }

puts "\nTree 1 has #{p_nodes1.size} <p> nodes"
puts "Tree 2 has #{p_nodes2.size} <p> nodes"

# Group by attributes
p_by_attrs1 = p_nodes1.group_by(&:attributes)
p_by_attrs2 = p_nodes2.group_by(&:attributes)

puts "\nTree 1 <p> nodes by attributes:"
p_by_attrs1.each do |attrs, nodes|
  puts "  #{attrs.inspect}: #{nodes.size} nodes"
end

puts "\nTree 2 <p> nodes by attributes:"
p_by_attrs2.each do |attrs, nodes|
  puts "  #{attrs.inspect}: #{nodes.size} nodes"
end

# Look at signatures
require_relative "../lib/canon/tree_diff/core/node_signature"

puts "\n#{'=' * 80}"
puts "ANALYZING SIGNATURES"
puts "=" * 80

# Get page-break <p> nodes
page_break_p1 = p_nodes1.select { |n| n.attributes["class"] == "page-break" }
page_break_p2 = p_nodes2.select { |n| n.attributes["class"] == "page-break" }

puts "\nFile 1 has #{page_break_p1.size} <p class=\"page-break\"> nodes"
puts "File 2 has #{page_break_p2.size} <p class=\"page-break\"> nodes"

if page_break_p1.any?
  puts "\nFirst 3 signatures from File 1:"
  page_break_p1.first(3).each_with_index do |node, i|
    sig = Canon::TreeDiff::Core::NodeSignature.for(node)
    puts "  #{i + 1}. #{sig}"
    puts "     Children: #{node.children.size}"
    if node.children.any?
      node.children.each do |child|
        child_sig = Canon::TreeDiff::Core::NodeSignature.for(child)
        puts "       - #{child.label}: #{child_sig}"
      end
    end
  end
end

if page_break_p2.any?
  puts "\nFirst 3 signatures from File 2:"
  page_break_p2.first(3).each_with_index do |node, i|
    sig = Canon::TreeDiff::Core::NodeSignature.for(node)
    puts "  #{i + 1}. #{sig}"
    puts "     Children: #{node.children.size}"
    if node.children.any?
      node.children.each do |child|
        child_sig = Canon::TreeDiff::Core::NodeSignature.for(child)
        puts "       - #{child.label}: #{child_sig}"
      end
    end
  end
end

# Run hash matcher
puts "\n#{'=' * 80}"
puts "RUNNING HASH MATCHER"
puts "=" * 80

options = {
  attribute_order: :ignore,
  text_content: :normalize,
}

matcher = Canon::TreeDiff::Matchers::HashMatcher.new(tree1, tree2, options)
matching = matcher.match

puts "\nTotal matched pairs: #{matching.size}"

# Check how many <p> nodes were matched
matched_p1 = p_nodes1.count { |n| matching.matched1?(n) }
matched_p2 = p_nodes2.count { |n| matching.matched2?(n) }

puts "Matched <p> from tree1: #{matched_p1}/#{p_nodes1.size}"
puts "Matched <p> from tree2: #{matched_p2}/#{p_nodes2.size}"

matched_page_break_p1 = page_break_p1.count { |n| matching.matched1?(n) }
matched_page_break_p2 = page_break_p2.count { |n| matching.matched2?(n) }

puts "Matched <p class=\"page-break\"> from tree1: #{matched_page_break_p1}/#{page_break_p1.size}"
puts "Matched <p class=\"page-break\"> from tree2: #{matched_page_break_p2}/#{page_break_p2.size}"

# Check unmatched page-break <p> nodes
unmatched_p1 = page_break_p1.reject { |n| matching.matched1?(n) }
unmatched_p2 = page_break_p2.reject { |n| matching.matched2?(n) }

puts "\nUnmatched <p class=\"page-break\"> from tree1: #{unmatched_p1.size}"
puts "Unmatched <p class=\"page-break\"> from tree2: #{unmatched_p2.size}"

if unmatched_p1.any?
  puts "\nFirst unmatched from tree1:"
  node = unmatched_p1.first
  puts "  Path: #{node.xpath}"
  puts "  Signature: #{Canon::TreeDiff::Core::NodeSignature.for(node)}"
  puts "  Children: #{node.children.size}"
  node.children.each do |child|
    puts "    - #{child.label}: value=#{child.value.inspect}, attrs=#{child.attributes.inspect}"
  end
end

if unmatched_p2.any?
  puts "\nFirst unmatched from tree2:"
  node = unmatched_p2.first
  puts "  Path: #{node.xpath}"
  puts "  Signature: #{Canon::TreeDiff::Core::NodeSignature.for(node)}"
  puts "  Children: #{node.children.size}"
  node.children.each do |child|
    puts "    - #{child.label}: value=#{child.value.inspect}, attrs=#{child.attributes.inspect}"
  end
end
