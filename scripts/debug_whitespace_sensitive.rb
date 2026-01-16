#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/canon"
require "nokogiri"

expected = <<~HTML
  <pre>

  </pre>
HTML

actual = <<~HTML
  <pre>    </pre>
HTML

# Parse and inspect the trees directly
puts "=== Tree Inspection ==="
doc1 = Nokogiri::HTML(expected)
doc2 = Nokogiri::HTML(actual)

pre1 = doc1.at_css("pre")
pre2 = doc2.at_css("pre")

puts "Pre1 text: #{pre1.text.inspect}"
puts "Pre1 text length: #{pre1.text.length}"
puts "Pre1 text bytes: #{pre1.text.bytes.inspect}"

puts "\nPre2 text: #{pre2.text.inspect}"
puts "Pre2 text length: #{pre2.text.length}"
puts "Pre2 text bytes: #{pre2.text.bytes.inspect}"

# Now build trees using the adapter
adapter = Canon::TreeDiff::Adapters::HTMLAdapter.new
tree1 = adapter.to_tree(doc1)
tree2 = adapter.to_tree(doc2)

# Check signatures
# tree1 structure: html -> body -> pre
body1 = tree1.children.first
pre1_node = body1.children.find { |c| c.label == "pre" }
body2 = tree2.children.first
pre2_node = body2.children.find { |c| c.label == "pre" }

puts "\n=== Signatures ==="
if pre1_node && pre2_node
  sig1 = Canon::TreeDiff::Core::NodeSignature.for(pre1_node)
  sig2 = Canon::TreeDiff::Core::NodeSignature.for(pre2_node)
  puts "Pre1 label: #{pre1_node.label}, value: #{pre1_node.value.inspect}"
  puts "Pre1 signature: #{sig1}"
  puts "Pre2 label: #{pre2_node.label}, value: #{pre2_node.value.inspect}"
  puts "Pre2 signature: #{sig2}"
  puts "Signatures equal: #{sig1 == sig2}"
else
  puts "ERROR: Could not find <pre> nodes"
  puts "Body1 children: #{body1.children.map(&:label)}"
  puts "Body2 children: #{body2.children.map(&:label)}"
end

def print_tree(node, indent = 0)
  prefix = "  " * indent
  puts "#{prefix}<#{node.label}>"
  puts "#{prefix}  value: #{node.value.inspect}" if node.value
  puts "#{prefix}  attrs: #{node.attributes}" unless node.attributes.empty?
  node.children.each { |child| print_tree(child, indent + 1) }
end

puts "\n=== Tree 1 ==="
print_tree(tree1)

puts "\n=== Tree 2 ==="
print_tree(tree2)

# Now test comparison
puts "\n=== Comparison ==="

# Test using TreeDiff directly
require_relative "../lib/canon/tree_diff/tree_diff_integrator"
integrator = Canon::TreeDiff::TreeDiffIntegrator.new(
  format: :html,
  options: {},
)

puts "\n=== Direct TreeDiff Test ==="
diff_result = integrator.diff(doc1, doc2)
puts "Operations count: #{diff_result[:operations].size}"
diff_result[:operations].each_with_index do |op, idx|
  puts "\nOperation #{idx + 1}:"
  puts "  Type: #{op.type}"
  puts "  Node: #{begin
    op[:node]&.label
  rescue StandardError
    'N/A'
  end}"
  if op[:node]
    puts "  Value: #{begin
      op[:node]&.value.inspect
    rescue StandardError
      'N/A'
    end}"
  end
end

# Convert operations to DiffNodes
puts "\n=== Operation Conversion ==="
converter = Canon::TreeDiff::OperationConverter.new(
  format: :html,
  match_options: {},
)
diff_nodes = converter.convert(diff_result[:operations])
puts "Converted DiffNodes count: #{diff_nodes.size}"
diff_nodes.each_with_index do |dn, idx|
  puts "\nDiffNode #{idx + 1}:"
  puts "  Dimension: #{dn.dimension}"
  puts "  Normative: #{dn.normative?}"
  puts "  Reason: #{dn.reason}"
  puts "  Node1: #{begin
    dn.node1.inspect
  rescue StandardError
    'nil'
  end}"
  puts "  Node2: #{begin
    dn.node2.inspect
  rescue StandardError
    'nil'
  end}"
end

# Now test via Canon::Comparison
puts "\n=== Canon::Comparison Result (with :semantic) ==="
result = Canon::Comparison.equivalent?(
  expected,
  actual,
  format: :html,
  diff_algorithm: :semantic,
  verbose: true,
)

puts "Result class: #{result.class}"
puts "Equivalent: #{result.equivalent?}"
puts "Differences count: #{result.differences.size}"
puts "Has normative diffs: #{result.has_normative_diffs?}"

puts "\n=== Trying with :semantic_tree ==="
result2 = Canon::Comparison.equivalent?(
  expected,
  actual,
  format: :html,
  diff_algorithm: :semantic_tree,
  verbose: true,
)

puts "Result class: #{result2.class}"
if result2.is_a?(Canon::Comparison::ComparisonResult)
  puts "Equivalent: #{result2.equivalent?}"
  puts "Differences count: #{result2.differences.size}"
else
  puts "Result: #{result2.inspect}"
end

result.differences.each_with_index do |diff, idx|
  puts "\n--- Diff #{idx + 1} ---"
  puts "Dimension: #{diff.dimension}"
  puts "Normative: #{diff.normative?}"
  puts "Reason: #{diff.reason}"
  if diff.node1
    puts "Node1 type: #{diff.node1.class}"
    puts "Node1 name: #{begin
      diff.node1.name
    rescue StandardError
      'N/A'
    end}"
    puts "Node1 text: #{begin
      diff.node1.text.inspect
    rescue StandardError
      'N/A'
    end}"
  end
  if diff.node2
    puts "Node2 type: #{diff.node2.class}"
    puts "Node2 name: #{begin
      diff.node2.name
    rescue StandardError
      'N/A'
    end}"
    puts "Node2 text: #{begin
      diff.node2.text.inspect
    rescue StandardError
      'N/A'
    end}"
  end
end
