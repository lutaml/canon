#!/usr/bin/env ruby
# frozen_string_literal: true

# Detailed investigation of classification in actual failing tests

require "bundler/setup"

# Actual failing tests from the 43 common failures
FAILING_TESTS = [
  { file: "blocks_spec.rb", line: 352, desc: "examples" },
  { file: "cleanup_spec.rb", line: 180, desc: "tables with tfoot" },
  { file: "figures_spec.rb", line: 5, desc: "figures" },
  { file: "inline_spec.rb", line: 1012, desc: "inline formatting" },
  { file: "sourcecode_spec.rb", line: 124, desc: "sourcecode" },
].freeze

def run_test_with_verbose(test_info, algorithm)
  isodoc_path = File.expand_path("~/src/mn/isodoc")
  test_path = "spec/isodoc/#{test_info[:file]}:#{test_info[:line]}"

  puts "\n--- #{algorithm.upcase} Algorithm ---"

  # Run test and capture full output
  cmd = "cd #{isodoc_path} && " \
        "CANON_DIFF_ALGORITHM=#{algorithm} " \
        "CANON_VERBOSE=true " \
        "bundle exec rspec #{test_path} 2>&1"

  output = `#{cmd}`

  # Check result
  if output.include?("0 failures")
    puts "✅ PASSED - No classification to check"
    return nil
  elsif !output.include?("1 failure")
    puts "⚠️  Unexpected result"
    return nil
  end

  puts "❌ FAILED - Analyzing diff output..."

  # Extract and analyze dimensions
  analyze_dimensions(output)

  output
end

def analyze_dimensions(output)
  # Look for dimension mentions in various formats
  dimensions = {}

  # Pattern 1: DIFFERENCE blocks
  output.scan(/DIFFERENCE.*?dimension:\s*(\w+).*?normative:\s*(\w+)/mi) do |dim, norm|
    dim_sym = dim.downcase.to_sym
    is_normative = norm.downcase == "true"
    dimensions[dim_sym] ||= { normative: 0, informative: 0 }
    if is_normative
      dimensions[dim_sym][:normative] += 1
    else
      dimensions[dim_sym][:informative] += 1
    end
  end

  # Pattern 2: Simple dimension mentions
  output.scan(/(?:dimension|Dimension):\s*(\w+)/i) do |match|
    dim_sym = match[0].downcase.to_sym
    dimensions[dim_sym] ||= { normative: 0, informative: 0, unknown: 0 }
    dimensions[dim_sym][:unknown] ||= 0
    dimensions[dim_sym][:unknown] += 1
  end

  if dimensions.any?
    puts "\n📊 Dimensions found:"
    dimensions.each do |dim, counts|
      puts "   #{dim}:"
      counts.each do |type, count|
        puts "      #{type}: #{count}" if count.positive?
      end
    end
  else
    puts "\n⚠️  No dimension information extracted"

    # Try to find any diff-related output
    if /expected.*to eq/mi.match?(output)
      puts "   Found RSpec expectation failure"
    end
    if /differ/i.match?(output)
      puts "   Found 'differ' mentions: #{output.scan(/differ/i).length}"
    end
  end

  # Check for specific match option mentions
  check_match_options_usage(output)
end

def check_match_options_usage(output)
  puts "\n🔧 Match Options Application:"

  # Check if attribute_order is mentioned
  if /attribute.order/i.match?(output)
    attr_order_count = output.scan(/attribute.order/i).length
    puts "   ✓ attribute_order mentioned (#{attr_order_count} times)"
    puts "     Expected: INFORMATIVE (match option: ignore)"
  end

  # Check if text normalization is mentioned
  if /text.*normaliz/i.match?(output)
    puts "   ✓ text normalization mentioned"
    puts "     Expected: differences after normalization = NORMATIVE"
  end

  # Check if whitespace is mentioned
  if /whitespace/i.match?(output)
    ws_count = output.scan(/whitespace/i).length
    puts "   ✓ whitespace mentioned (#{ws_count} times)"
    puts "     Expected: structural_whitespace = NORMATIVE (normalized)"
  end

  # Check if comments are mentioned
  if /comment/i.match?(output)
    comment_count = output.scan(/comment/i).length
    puts "   ✓ comments mentioned (#{comment_count} times)"
    puts "     Expected: INFORMATIVE (match option: ignore for HTML)"
  end
end

def compare_algorithms(test_info)
  puts "\n#{'=' * 80}"
  puts "Test: #{test_info[:file]}:#{test_info[:line]}"
  puts "Description: #{test_info[:desc]}"
  puts "=" * 80

  dom_output = run_test_with_verbose(test_info, "dom")
  semantic_output = run_test_with_verbose(test_info, "semantic")

  if dom_output && semantic_output
    puts "\n🔍 Comparing algorithm outputs:"

    # Extract dimension info from both
    dom_dims = extract_dimension_list(dom_output)
    sem_dims = extract_dimension_list(semantic_output)

    if dom_dims == sem_dims
      puts "   ✅ Both algorithms report same dimensions: #{dom_dims.sort.join(', ')}"
    else
      puts "   ⚠️  Algorithms report different dimensions:"
      puts "      DOM:      #{dom_dims.sort.join(', ')}"
      puts "      Semantic: #{sem_dims.sort.join(', ')}"
      puts "      Only in DOM: #{(dom_dims - sem_dims).sort.join(', ')}" if (dom_dims - sem_dims).any?
      puts "      Only in Semantic: #{(sem_dims - dom_dims).sort.join(', ')}" if (sem_dims - dom_dims).any?
    end
  end
end

def extract_dimension_list(output)
  dimensions = []
  output.scan(/(?:dimension|Dimension):\s*(\w+)/i) do |match|
    dim = match[0].downcase.to_sym
    dimensions << dim unless dimensions.include?(dim)
  end
  dimensions
end

def main
  puts "Detailed Canon Classification Investigation"
  puts "Examining actual failing tests to verify correct classification"
  puts "\nMatch Options for HTML (default isodoc format):"
  puts "  - attribute_order: ignore → INFORMATIVE ✓"
  puts "  - text_content: normalize → NORMATIVE (after normalization)"
  puts "  - structural_whitespace: normalize → NORMATIVE (after normalization)"
  puts "  - comments: ignore → INFORMATIVE ✓"
  puts "  - attribute_values: strict → NORMATIVE ✓"
  puts "  - attribute_presence: strict → NORMATIVE ✓"

  FAILING_TESTS.each do |test_info|
    compare_algorithms(test_info)
    puts "\n"
  end

  puts "=" * 80
  puts "Investigation Complete"
  puts "=" * 80
  puts "\nKey Findings to Check:"
  puts "1. Do both algorithms classify the same dimensions?"
  puts "2. Are 'ignore' dimensions (attribute_order, comments) INFORMATIVE?"
  puts "3. Are 'normalize' dimensions NORMATIVE when differences persist?"
  puts "4. Are 'strict' dimensions always NORMATIVE?"
end

main if __FILE__ == $PROGRAM_NAME
