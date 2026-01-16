#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "canon"
require "nokogiri"

# Test mixed content element extraction
def test_mixed_content_extraction
  puts "=" * 80
  puts "Testing Mixed Content Text Extraction"
  puts "=" * 80

  # Create test XML with mixed content
  xml_str = <<~XML
    <root>
      <formattedAddress>123 Main St<br/>Springfield, IL<br/>62701</formattedAddress>
      <normalText>Just plain text</normalText>
      <withSpaces>  Text with   spaces  </withSpaces>
      <withNewlines>Text
      with
      newlines</withNewlines>
    </root>
  XML

  doc = Nokogiri::XML(xml_str)

  # Test each element
  doc.root.element_children.each do |elem|
    puts "\nElement: <#{elem.name}>"
    puts "  Content: #{elem.content.inspect}"

    # Extract text nodes
    text_nodes = elem.children.select(&:text?)
    puts "  Text nodes count: #{text_nodes.size}"
    text_nodes.each_with_index do |node, i|
      puts "    [#{i}]: #{node.text.inspect}"
    end

    # Join text
    joined = text_nodes.map(&:text).join
    puts "  Joined text: #{joined.inspect}"

    # Show normalization
    normalized = joined.gsub(/\s+/, " ").strip
    puts "  Normalized: #{normalized.inspect}"

    # Element children
    elem_children = elem.element_children
    puts "  Element children: #{elem_children.map(&:name).inspect}"
  end
end

# Test with Canon adapter
def test_with_adapter
  puts "\n#{'=' * 80}"
  puts "Testing with Canon XML Adapter"
  puts "=" * 80

  xml_str = <<~XML
    <root>
      <formattedAddress>123 Main St<br/>Springfield, IL<br/>62701</formattedAddress>
    </root>
  XML

  doc = Nokogiri::XML(xml_str)

  adapter = Canon::TreeDiff::Adapters::XMLAdapter.new
  tree = adapter.to_tree(doc)

  # Find the formattedAddress node
  address_node = tree.children.first

  puts "\nTreeNode for formattedAddress:"
  puts "  Label: #{address_node.label}"
  puts "  Value: #{address_node.value.inspect}"
  puts "  Children count: #{address_node.children.size}"
  address_node.children.each do |child|
    puts "    Child: #{child.label} = #{child.value.inspect}"
  end
end

# Test normalization in operation detector
def test_normalization_comparison
  puts "\n#{'=' * 80}"
  puts "Testing Normalization in Comparison"
  puts "=" * 80

  # Two versions with different whitespace in mixed content
  xml1 = <<~XML
    <root>
      <address>123 Main St<br/>Springfield, IL<br/>62701</address>
    </root>
  XML

  xml2 = <<~XML
    <root>
      <address>123 Main St<br/>Springfield,  IL<br/>62701</address>
    </root>
  XML

  # Compare with whitespace_sensitive: false
  result = Canon.semantic_tree_diff(xml1, xml2,
                                    whitespace_sensitive: false,
                                    verbose: true)

  puts "\nComparison result:"
  puts "  Identical: #{result.identical?}"
  puts "  Normative differences: #{result.normative_differences?}"
  puts "  Informative differences: #{result.informative_differences?}"

  if result.operations.any?
    puts "\nOperations:"
    result.operations.each do |op|
      puts "  #{op.type}: #{op.path} - #{op.classification}"
      puts "    Old: #{op.old_value.inspect}" if op.old_value
      puts "    New: #{op.new_value.inspect}" if op.new_value
    end
  end
end

# Run all tests
test_mixed_content_extraction
test_with_adapter
test_normalization_comparison
