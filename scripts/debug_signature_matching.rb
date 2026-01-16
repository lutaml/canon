#!/usr/bin/env ruby
# frozen_string_literal: true

# Debug signature matching to understand why elements aren't matching
# Usage: ruby scripts/debug_signature_matching.rb

require_relative "../lib/canon"
require "nokogiri"

# Sample XML with semx elements that should match
xml1 = <<~XML
  <p>
    <fmt-concept>
      <semx element="title" source="_">word</semx>
    </fmt-concept>
  </p>
XML

xml2 = <<~XML
  <p>
    <fmt-concept>
      <semx element="concept" source="_">word</semx>
    </fmt-concept>
  </p>
XML

puts "=" * 80
puts "SIGNATURE MATCHING DEBUG"
puts "=" * 80

# Parse both
doc1 = Nokogiri::XML(xml1)
doc2 = Nokogiri::XML(xml2)

# Create adapter
adapter = Canon::TreeDiff::Adapters::XMLAdapter.new

# Convert to tree
tree1 = adapter.to_tree(doc1.root)
tree2 = adapter.to_tree(doc2.root)

puts "\nTree 1 structure:"
def print_tree(node, indent = 0)
  prefix = "  " * indent
  if node.text?
    puts "#{prefix}#text: #{node.value.inspect}"
  else
    attrs = node.attributes.empty? ? "" : " {#{node.attributes.inspect}}"
    puts "#{prefix}<#{node.label}>#{attrs}"
    node.children.each { |c| print_tree(c, indent + 1) }
  end
end

print_tree(tree1)

puts "\nTree 2 structure:"
print_tree(tree2)

# Get semx nodes
semx1 = tree1.descendants.find { |n| n.label == "semx" }
semx2 = tree2.descendants.find { |n| n.label == "semx" }

puts "\n#{'-' * 80}"
puts "SEMX NODE COMPARISON"
puts "-" * 80

puts "\nSemx 1:"
puts "  Label: #{semx1.label}"
puts "  Value: #{semx1.value.inspect}"
puts "  Attributes: #{semx1.attributes.inspect}"

puts "\nSemx 2:"
puts "  Label: #{semx2.label}"
puts "  Value: #{semx2.value.inspect}"
puts "  Attributes: #{semx2.attributes.inspect}"

# Compute signatures
sig1_strict = Canon::TreeDiff::Core::NodeSignature.for(semx1,
                                                       include_attributes: true)
sig2_strict = Canon::TreeDiff::Core::NodeSignature.for(semx2,
                                                       include_attributes: true)

sig1_loose = Canon::TreeDiff::Core::NodeSignature.for(semx1,
                                                      include_attributes: false)
sig2_loose = Canon::TreeDiff::Core::NodeSignature.for(semx2,
                                                      include_attributes: false)

puts "\n#{'-' * 80}"
puts "SIGNATURE COMPARISON"
puts "-" * 80

puts "\nStrict signatures (with attributes):"
puts "  Semx 1: #{sig1_strict.signature_string}"
puts "  Semx 2: #{sig2_strict.signature_string}"
puts "  Match? #{sig1_strict == sig2_strict}"

puts "\nLoose signatures (without attributes):"
puts "  Semx 1: #{sig1_loose.signature_string}"
puts "  Semx 2: #{sig2_loose.signature_string}"
puts "  Match? #{sig1_loose == sig2_loose}"

puts "\n#{'-' * 80}"
puts "ANALYSIS"
puts "-" * 80

if sig1_strict != sig2_strict
  puts "\n⚠️  ISSUE FOUND:"
  puts "Strict signatures don't match due to attribute differences!"
  puts "This prevents HashMatcher from considering these nodes as candidates."
  puts "\nDifference:"
  puts "  File 1: element='title'"
  puts "  File 2: element='concept'"
  puts "\nSOLUTION:"
  puts "HashMatcher should use LOOSE signatures (no attributes) to find candidates,"
  puts "then check attributes separately during matching."
end

puts "\n#{'=' * 80}"
