#!/usr/bin/env ruby
# frozen_string_literal: true

# Parse test results from a log file
def parse_failures(log_file)
  lines = File.readlines(log_file)

  failures = []
  lines.each do |line|
    # Strip ANSI color codes first
    clean_line = line.gsub(/\e\[\d+m/, "")

    # Match rspec failure format
    if clean_line =~ /^rspec (\.\/spec\/\S+:\d+)/
      failures << $1
    end
  end

  failures
end

# Main
semantic_log = "/tmp/semantic_after_mixed_content_fix.log"
dom_log = "/tmp/dom_baseline.log"

puts "=" * 80
puts "Current Semantic Tree Algorithm Status"
puts "=" * 80

if File.exist?(semantic_log)
  semantic_failures = parse_failures(semantic_log)
  puts "\nSemantic failures: #{semantic_failures.size}"

  if File.exist?(dom_log)
    dom_failures = parse_failures(dom_log)
    puts "DOM failures: #{dom_failures.size}"

    # Calculate differences
    false_positives = semantic_failures - dom_failures
    false_negatives = dom_failures - semantic_failures
    common = semantic_failures & dom_failures

    puts "\n#{'=' * 80}"
    puts "Comparison with DOM Baseline"
    puts "=" * 80
    puts "False Positives (semantic fails, DOM passes): #{false_positives.size}"
    puts "False Negatives (semantic passes, DOM fails): #{false_negatives.size}"
    puts "Common failures (both fail): #{common.size}"

    if false_positives.any?
      puts "\n#{'-' * 80}"
      puts "FALSE POSITIVES (Need to fix - #{false_positives.size}):"
      puts "-" * 80
      false_positives.sort.each { |f| puts "  #{f}" }
    end

    if false_negatives.any?
      puts "\n#{'-' * 80}"
      puts "FALSE NEGATIVES (Investigate - #{false_negatives.size}):"
      puts "-" * 80
      false_negatives.sort.each { |f| puts "  #{f}" }
    end

    # Progress tracking
    puts "\n#{'=' * 80}"
    puts "Progress Tracking"
    puts "=" * 80
    puts "Initial state:     62 failures (29 FP, 5 FN, 33 common)"
    puts "After metadata:    56 failures (23 FP, 5 FN, 33 common)"
    puts "After mixed content: #{semantic_failures.size} failures (#{false_positives.size} FP, #{false_negatives.size} FN, #{common.size} common)"
    puts "Target (DOM parity): #{dom_failures.size} failures (0 FP, 0 FN, #{dom_failures.size} common)"

    improvement = 56 - semantic_failures.size
    remaining = semantic_failures.size - dom_failures.size
    puts "\nImprovement: #{improvement} tests fixed"
    puts "Remaining gap: #{remaining} tests"

  else
    puts "\nWarning: DOM baseline not found at #{dom_log}"
    puts "Semantic failures:"
    semantic_failures.sort.each { |f| puts "  #{f}" }
  end
else
  puts "Error: Semantic log not found at #{semantic_log}"
end
