#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to extract and analyze the 16 false positive test cases
# Usage: ruby scripts/extract_false_positives.rb

require "bundler/setup"
require "canon"

# Map of test files to line numbers
FALSE_POSITIVES = {
  "blocks_spec.rb" => [352],
  "footnotes_spec.rb" => [740],
  "inline_spec.rb" => [1012, 1251],
  "postproc_spec.rb" => [948],
  "postproc_word_spec.rb" => [372, 576],
  "presentation_xml_numbers_override_spec.rb" => [2095],
  "presentation_xml_spec.rb" => [1288, 1500],
  "ref_spec.rb" => [906],
  "sourcecode_spec.rb" => [124, 610],
  "terms_spec.rb" => [1445],
  "xref_format_spec.rb" => [628],
  "xref_spec.rb" => [315],
}.freeze

ISODOC_SPEC_DIR = File.expand_path("../../mn/isodoc/spec/isodoc", __dir__)

def extract_test_context(file_path, line_number)
  return nil unless File.exist?(file_path)

  lines = File.readlines(file_path)

  # Find the start of the test block (looking backward for 'it "')
  start_line = line_number - 1
  while start_line.positive?
    break if /^\s*it\s+["']/.match?(lines[start_line])

    start_line -= 1
  end

  # Find the end of the test block (looking forward for matching 'end')
  end_line = line_number - 1
  depth = 0
  while end_line < lines.length
    line = lines[end_line]
    depth += 1 if /\b(do|begin)\b/.match?(line)
    depth -= 1 if /\bend\b/.match?(line)
    break if depth <= 0 && end_line > start_line

    end_line += 1
  end

  # Extract test description
  test_desc = lines[start_line].match(/it\s+["'](.+?)["']/)&.captures&.first || "Unknown test"

  {
    file: File.basename(file_path),
    line: line_number,
    description: test_desc,
    content: lines[start_line..end_line].join,
  }
end

def analyze_test_for_patterns(test_info)
  content = test_info[:content]

  patterns = []

  # Check for various patterns
  patterns << "whitespace_in_pre" if /<pre[^>]*>.*?<\/pre>/m.match?(content)
  patterns << "sourcecode_element" if /sourcecode/i.match?(content)
  patterns << "metadata_elements" if /<(bookmark|span|meta|a name=)/.match?(content)
  patterns << "mixed_content" if /<[^>]+>[^<]*<[^>]+>/.match?(content)
  patterns << "attribute_order" if /\s+\w+=["'][^"']*["']\s+\w+=["'][^"']*["']/.match?(content)
  patterns << "nested_formatting" if /<(strong|em|i|b|u)[^>]*>.*?<(strong|em|i|b|u)/m.match?(content)

  patterns
end

puts "=" * 80
puts "EXTRACTING FALSE POSITIVE TEST CASES"
puts "=" * 80

all_tests = []
pattern_summary = Hash.new(0)

FALSE_POSITIVES.each do |file, line_numbers|
  file_path = File.join(ISODOC_SPEC_DIR, file)

  puts "\n#{file}:"

  line_numbers.each do |line|
    test_info = extract_test_context(file_path, line)

    if test_info
      patterns = analyze_test_for_patterns(test_info)
      test_info[:patterns] = patterns
      all_tests << test_info

      patterns.each { |p| pattern_summary[p] += 1 }

      puts "  Line #{line}: #{test_info[:description]}"
      puts "    Patterns: #{patterns.join(', ')}" unless patterns.empty?
    else
      puts "  Line #{line}: ⚠️  Could not extract test"
    end
  end
end

puts "\n#{'=' * 80}"
puts "PATTERN SUMMARY"
puts "=" * 80

pattern_summary.sort_by { |_, count| -count }.each do |pattern, count|
  puts "  #{pattern}: #{count} occurrences"
end

puts "\n#{'=' * 80}"
puts "DETAILED TEST EXTRACTION"
puts "=" * 80

# Save detailed output
output_file = "false_positive_analysis.txt"
File.open(output_file, "w") do |f|
  all_tests.each_with_index do |test, i|
    f.puts "\n#{'=' * 80}"
    f.puts "TEST #{i + 1}: #{test[:file]}:#{test[:line]}"
    f.puts "=" * 80
    f.puts "Description: #{test[:description]}"
    f.puts "Patterns: #{test[:patterns].join(', ')}"
    f.puts "\nTest Code:"
    f.puts "-" * 80
    f.puts test[:content]
  end
end

puts "\nDetailed analysis saved to: #{output_file}"
puts "\nTotal false positives analyzed: #{all_tests.length}"
