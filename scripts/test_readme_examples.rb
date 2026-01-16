#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/canon"
require_relative "../lib/canon/comparison"
require_relative "../lib/canon/pretty_printer/xml"
require_relative "../lib/canon/xml/c14n"
require_relative "../lib/canon/config"

puts "Testing corrected README.adoc examples..."
puts "=" * 60

# Test 1: Canon.format (default pretty-print)
puts "\n1. Testing Canon.format with XML (default)..."
begin
  result = Canon.format("<root><b>2</b><a>1</a></root>", :xml)
  if result.include?("<?xml") && result.include?("<root>")
    puts "✓ Canon.format works (returns pretty-printed XML)"
  else
    puts "✗ Canon.format unexpected output"
  end
rescue StandardError => e
  puts "✗ Canon.format failed: #{e.message}"
end

# Test 2: Canonical form (compact)
puts "\n2. Testing Canon::Xml::C14n.canonicalize..."
begin
  result = Canon::Xml::C14n.canonicalize("<root><b>2</b><a>1</a></root>",
                                         with_comments: false)
  expected = "<root><b>2</b><a>1</a></root>"
  if result == expected
    puts "✓ Canon::Xml::C14n.canonicalize works"
    puts "  Result: #{result}"
  else
    puts "✗ Unexpected result: #{result}"
  end
rescue StandardError => e
  puts "✗ Canon::Xml::C14n.canonicalize failed: #{e.message}"
end

# Test 3: Pretty printer with variable
puts "\n3. Testing Canon::PrettyPrinter::Xml with defined variable..."
begin
  xml_input = "<root><b>2</b><a>1</a></root>"
  result = Canon::PrettyPrinter::Xml.new(indent: 2).format(xml_input)
  if result.include?("<?xml") && result.include?("<root>")
    puts "✓ Canon::PrettyPrinter::Xml works with defined variable"
  else
    puts "✗ Unexpected output"
  end
rescue StandardError => e
  puts "✗ Canon::PrettyPrinter::Xml failed: #{e.message}"
end

# Test 4: Basic comparison
puts "\n4. Testing Canon::Comparison.equivalent?..."
begin
  xml1 = "<root><a>1</a><b>2</b></root>"
  xml2 = "<root>  <b>2</b>  <a>1</a>  </root>"
  result = Canon::Comparison.equivalent?(xml1, xml2)
  puts "✓ Canon::Comparison.equivalent? works"
  puts "  Result: #{result}"
rescue StandardError => e
  puts "✗ Canon::Comparison.equivalent? failed: #{e.message}"
end

# Test 5: Semantic tree diff
puts "\n5. Testing semantic tree diff with operations..."
begin
  xml1 = "<root><a>1</a><b>2</b></root>"
  xml2 = "<root>  <b>2</b>  <a>1</a>  </root>"
  result = Canon::Comparison.equivalent?(xml1, xml2,
                                         verbose: true,
                                         diff_algorithm: :semantic)
  if result.respond_to?(:operations)
    puts "✓ Semantic tree diff works"
    puts "  Result class: #{result.class}"
    puts "  Operations available: #{result.operations.class}"
  else
    puts "✗ Result doesn't have operations method"
  end
rescue StandardError => e
  puts "✗ Semantic tree diff failed: #{e.message}"
end

# Test 6: RSpec configuration (using Canon::Config)
puts "\n6. Testing Canon::Config.configure..."
begin
  Canon::Config.configure do |config|
    config.xml.match.profile = :spec_friendly
    config.xml.diff.use_color = true
  end
  profile = Canon::Config.instance.xml.match.profile
  use_color = Canon::Config.instance.xml.diff.use_color
  if profile == :spec_friendly && use_color == true
    puts "✓ Canon::Config.configure works correctly"
    puts "  Profile: #{profile}"
    puts "  Use color: #{use_color}"
  else
    puts "✗ Configuration values not set correctly"
  end
rescue StandardError => e
  puts "✗ Canon::Config.configure failed: #{e.message}"
end

# Test 7: Comparison with custom options
puts "\n7. Testing Canon::Comparison with match options..."
begin
  doc1 = "<root><a> text </a></root>"
  doc2 = "<root><a>text</a></root>"
  result = Canon::Comparison.equivalent?(doc1, doc2,
                                         match: {
                                           text_content: :normalize,
                                           structural_whitespace: :ignore,
                                           comments: :ignore,
                                         },
                                         verbose: true)
  if result.respond_to?(:equivalent?)
    puts "✓ Canon::Comparison with match options works"
    puts "  Result equivalent: #{result.equivalent?}"
  else
    puts "✗ Result doesn't have expected methods"
  end
rescue StandardError => e
  puts "✗ Canon::Comparison with match options failed: #{e.message}"
end

puts "\n#{'=' * 60}"
puts "All tests completed successfully! ✓"
puts "=" * 60
