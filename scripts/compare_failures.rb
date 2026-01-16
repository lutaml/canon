#!/usr/bin/env ruby
# frozen_string_literal: true

# Compare semantic and DOM algorithm failures to identify false positives/negatives
# Usage: ruby scripts/compare_failures.rb /tmp/semantic_current.txt DOM_DIFF_RESULTS.md

require "set"

def parse_semantic_failures(file)
  failures = []
  File.readlines(file).each do |line|
    # Format: "rspec ./spec/isodoc/blocks_notes_spec.rb:494 # ..."
    if line =~ %r{rspec \./spec/isodoc/([a-z_]+_spec\.rb):(\d+)}
      failures << { file: $1, line: $2.to_i }
    end
  end
  failures
end

def parse_dom_failures(file)
  failures = []
  in_failures = false

  File.readlines(file).each do |line|
    if line.include?("Failed examples:")
      in_failures = true
      next
    end

    next unless in_failures

    # Stop at Coverage report
    break if line.include?("Coverage report")

    # Format: "rspec ./spec/isodoc/blocks_notes_spec.rb:494"
    if line =~ %r{rspec \./spec/isodoc/([a-z_]+_spec\.rb):(\d+)}
      failures << { file: $1, line: $2.to_i }
    end
  end

  failures
end

def categorize_failures(semantic, dom)
  semantic_set = Set.new(semantic.map { |f| "#{f[:file]}:#{f[:line]}" })
  dom_set = Set.new(dom.map { |f| "#{f[:file]}:#{f[:line]}" })

  {
    false_positives: semantic_set - dom_set, # Semantic fails, DOM passes
    false_negatives: dom_set - semantic_set, # DOM fails, Semantic passes
    common: semantic_set & dom_set, # Both fail (real failures)
  }
end

def group_by_spec(failures)
  failures.group_by { |f| f.split(":").first }.transform_values(&:count)
end

def main
  semantic_file = ARGV[0] || "/tmp/semantic_current.txt"
  dom_file = ARGV[1] || "DOM_DIFF_RESULTS.md"

  puts "Parsing semantic failures from: #{semantic_file}"
  semantic = parse_semantic_failures(semantic_file)

  puts "Parsing DOM failures from: #{dom_file}"
  dom = parse_dom_failures(dom_file)

  puts "\n#{'=' * 80}"
  puts "FAILURE COMPARISON SUMMARY"
  puts "=" * 80

  puts "\nTotal failures:"
  puts "  Semantic: #{semantic.size}"
  puts "  DOM:      #{dom.size}"

  categories = categorize_failures(semantic, dom)

  puts "\n#{'-' * 80}"
  puts "FALSE POSITIVES (Semantic fails, DOM passes) - #{categories[:false_positives].size}"
  puts "-" * 80
  puts "\nBy spec file:"
  group_by_spec(categories[:false_positives].to_a).sort_by do |_, v|
    -v
  end.each do |file, count|
    puts "  #{file}: #{count}"
  end

  puts "\nDetailed list:"
  categories[:false_positives].sort.each do |failure|
    puts "  #{failure}"
  end

  puts "\n#{'-' * 80}"
  puts "FALSE NEGATIVES (DOM fails, Semantic passes) - #{categories[:false_negatives].size}"
  puts "-" * 80
  puts "\nBy spec file:"
  group_by_spec(categories[:false_negatives].to_a).sort_by do |_, v|
    -v
  end.each do |file, count|
    puts "  #{file}: #{count}"
  end

  puts "\nDetailed list:"
  categories[:false_negatives].sort.each do |failure|
    puts "  #{failure}"
  end

  puts "\n#{'-' * 80}"
  puts "COMMON FAILURES (Both algorithms fail) - #{categories[:common].size}"
  puts "-" * 80
  puts "\nBy spec file:"
  group_by_spec(categories[:common].to_a).sort_by do |_, v|
    -v
  end.each do |file, count|
    puts "  #{file}: #{count}"
  end

  puts "\n#{'=' * 80}"
  puts "NEXT STEPS"
  puts "=" * 80
  puts "\n1. Fix false positives (#{categories[:false_positives].size} tests):"
  puts "   - These are cases where semantic is too strict"
  puts "   - DOM passes but semantic fails"
  puts "   - Fix these to reduce semantic failures"

  puts "\n2. Fix false negatives (#{categories[:false_negatives].size} tests):"
  puts "   - These are cases where semantic is too lenient"
  puts "   - Semantic passes but DOM fails"
  puts "   - Fix these to maintain correctness"

  puts "\n3. Common failures (#{categories[:common].size} tests):"
  puts "   - These are real test failures in both algorithms"
  puts "   - Will remain after parity is achieved"
  puts "   - May indicate actual test/code issues"

  # Save detailed results
  output_file = "/tmp/failure_comparison.txt"
  File.open(output_file, "w") do |f|
    f.puts "FALSE POSITIVES (#{categories[:false_positives].size}):"
    categories[:false_positives].sort.each { |fp| f.puts fp }
    f.puts "\nFALSE NEGATIVES (#{categories[:false_negatives].size}):"
    categories[:false_negatives].sort.each { |fn| f.puts fn }
    f.puts "\nCOMMON FAILURES (#{categories[:common].size}):"
    categories[:common].sort.each { |cf| f.puts cf }
  end

  puts "\nDetailed results saved to: #{output_file}"
end

main if __FILE__ == $PROGRAM_NAME
