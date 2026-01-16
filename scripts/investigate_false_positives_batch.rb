#!/usr/bin/env ruby
# frozen_string_literal: true

# Systematically investigate false positive failures
# Usage: ruby scripts/investigate_false_positives_batch.rb <spec_file:line> [<spec_file:line> ...]

require "bundler/setup"
require "fileutils"

# False positive test cases from XMLNS_FIX_VALIDATION.md
FALSE_POSITIVES = [
  "blocks_spec.rb:352",
  "footnotes_spec.rb:740",
  "inline_spec.rb:1012",
  "inline_spec.rb:1251",
  "postproc_spec.rb:948",
  "postproc_word_spec.rb:372",
  "postproc_word_spec.rb:576",
  "presentation_xml_numbers_override_spec.rb:2095",
  "presentation_xml_spec.rb:1288",
  "presentation_xml_spec.rb:1500",
  "ref_spec.rb:906",
  "sourcecode_spec.rb:124",
  "sourcecode_spec.rb:610",
  "terms_spec.rb:1445",
  "xref_format_spec.rb:628",
  "xref_spec.rb:315",
].freeze

def run_test(spec_file, line, algorithm)
  spec_path = File.expand_path("../../../mn/isodoc/spec/isodoc/#{spec_file}",
                               __dir__)

  unless File.exist?(spec_path)
    puts "  ❌ File not found: #{spec_path}"
    return nil
  end

  # Run with specific algorithm
  { "CANON_ALGORITHM" => algorithm }
  cmd = "cd #{File.dirname(spec_path)} && bundle exec rspec #{spec_path}:#{line} 2>&1"

  output = `#{cmd}`
  success = $?.success?

  { success: success, output: output }
end

def analyze_test(test_case)
  spec_file, line = test_case.split(":")

  puts "\n#{'=' * 80}"
  puts "ANALYZING: #{test_case}"
  puts "=" * 80

  # Run with DOM algorithm
  puts "\n1. Testing with DOM algorithm..."
  dom_result = run_test(spec_file, line, "dom")
  return unless dom_result

  dom_pass = dom_result[:success]
  puts "   Result: #{dom_pass ? '✅ PASS' : '❌ FAIL'}"

  # Run with Semantic algorithm
  puts "\n2. Testing with Semantic algorithm..."
  semantic_result = run_test(spec_file, line, "semantic")
  return unless semantic_result

  semantic_pass = semantic_result[:success]
  puts "   Result: #{semantic_pass ? '✅ PASS' : '❌ FAIL'}"

  # Analysis
  puts "\n#{'-' * 80}"
  puts "ANALYSIS:"
  puts "-" * 80

  if dom_pass && !semantic_pass
    puts "✅ CONFIRMED FALSE POSITIVE: DOM passes, Semantic fails"
    puts "\nThis test should be investigated to understand why semantic is too strict."

    # Extract failure details from semantic output
    if semantic_result[:output] =~ /Failure\/Error:(.+?)(?=\n\n|\z)/m
      failure_section = $1
      puts "\nFailure details:"
      puts failure_section.lines.take(20).join
    end

    :false_positive
  elsif !dom_pass && semantic_pass
    puts "⚠️  UNEXPECTED: This was listed as false positive but DOM fails, Semantic passes"
    puts "This is actually a false NEGATIVE, not a false positive!"
    :false_negative
  elsif dom_pass && semantic_pass
    puts "✅ BOTH PASS: This is no longer a false positive!"
    :fixed
  else
    puts "❌ BOTH FAIL: This is a common failure, not a false positive"
    :common_failure
  end
end

def main
  # Get test cases from arguments or use all false positives
  test_cases = if ARGV.empty?
                 FALSE_POSITIVES
               else
                 ARGV
               end

  puts "Investigating #{test_cases.size} false positive test cases..."

  results = {
    false_positive: [],
    false_negative: [],
    fixed: [],
    common_failure: [],
    error: [],
  }

  test_cases.each do |test_case|
    result = analyze_test(test_case)
    results[result || :error] << test_case
  end

  # Summary
  puts "\n#{'=' * 80}"
  puts "SUMMARY"
  puts "=" * 80

  puts "\n✅ Confirmed False Positives (need fixing): #{results[:false_positive].size}"
  results[:false_positive].each { |tc| puts "   - #{tc}" }

  puts "\n🎉 Already Fixed: #{results[:fixed].size}"
  results[:fixed].each { |tc| puts "   - #{tc}" }

  puts "\n⚠️  Misclassified (actually false negatives): #{results[:false_negative].size}"
  results[:false_negative].each { |tc| puts "   - #{tc}" }

  puts "\n❌ Common Failures: #{results[:common_failure].size}"
  results[:common_failure].each { |tc| puts "   - #{tc}" }

  puts "\n💥 Errors: #{results[:error].size}"
  results[:error].each { |tc| puts "   - #{tc}" }

  # Save detailed results
  output_file = "/tmp/false_positive_investigation.txt"
  File.open(output_file, "w") do |f|
    f.puts "FALSE POSITIVE INVESTIGATION RESULTS"
    f.puts "=" * 80
    f.puts "\nConfirmed False Positives (#{results[:false_positive].size}):"
    results[:false_positive].each { |tc| f.puts tc }
    f.puts "\nAlready Fixed (#{results[:fixed].size}):"
    results[:fixed].each { |tc| f.puts tc }
    f.puts "\nMisclassified (#{results[:false_negative].size}):"
    results[:false_negative].each { |tc| f.puts tc }
    f.puts "\nCommon Failures (#{results[:common_failure].size}):"
    results[:common_failure].each { |tc| f.puts tc }
  end

  puts "\nDetailed results saved to: #{output_file}"
end

main if __FILE__ == $PROGRAM_NAME
