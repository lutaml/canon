#!/usr/bin/env ruby
# frozen_string_literal: true

# Find the actual false positives by comparing DOM vs semantic failures

require "json"
require "set"

ISODOC_DIR = File.expand_path("../../../mn/isodoc", __dir__)

def run_tests(algorithm)
  puts "Running with CANON_ALGORITHM=#{algorithm}..."
  output_file = "/tmp/rspec_#{algorithm}_#{Process.pid}.json"
  cmd = "cd #{ISODOC_DIR} && CANON_ALGORITHM=#{algorithm} bundle exec rspec --format json --out #{output_file} 2>&1 >/dev/null"
  system(cmd)

  if File.exist?(output_file)
    content = File.read(output_file)
    File.delete(output_file)
    begin
      JSON.parse(content)
    rescue JSON::ParserError => e
      puts "Failed to parse JSON for #{algorithm}: #{e.message}"
      puts "First 200 chars: #{content[0..200]}"
      nil
    end
  else
    puts "Output file not created for #{algorithm}"
    nil
  end
end

def extract_failures(results)
  return [] unless results && results["examples"]

  results["examples"].select { |ex| ex["status"] == "failed" }.map do |ex|
    # Extract file and line from id
    # Format: "./spec/isodoc/blocks_spec.rb[1:1:1]"
    if ex["id"] =~ %r{\./(spec/isodoc/[^\[]+)\[}
      file = $1
      line = ex["line_number"]
      "#{file}:#{line}"
    end
  end.compact
end

puts "=" * 80
puts "FINDING ACTUAL FALSE POSITIVES"
puts "=" * 80
puts

# Run with both algorithms
dom_results = run_tests("dom")
semantic_results = run_tests("semantic")

if dom_results.nil? || semantic_results.nil?
  puts "ERROR: Failed to get test results"
  exit 1
end

# Extract failure lists
dom_failures = Set.new(extract_failures(dom_results))
semantic_failures = Set.new(extract_failures(semantic_results))

puts "DOM failures:      #{dom_failures.size}"
puts "Semantic failures: #{semantic_failures.size}"
puts

# Find false positives (pass with DOM, fail with semantic)
false_positives = semantic_failures - dom_failures

puts "=" * 80
puts "FALSE POSITIVES (#{false_positives.size})"
puts "Tests that PASS with DOM but FAIL with semantic:"
puts "=" * 80

if false_positives.empty?
  puts "✅ NO FALSE POSITIVES FOUND!"
  puts "DOM and semantic algorithms have perfect parity!"
else
  false_positives.sort.each_with_index do |test, idx|
    puts "#{idx + 1}. #{test}"
  end
end

# Find false negatives (fail with DOM, pass with semantic)
false_negatives = dom_failures - semantic_failures

puts
puts "=" * 80
puts "FALSE NEGATIVES (#{false_negatives.size})"
puts "Tests that FAIL with DOM but PASS with semantic:"
puts "=" * 80

if false_negatives.empty?
  puts "✅ NO FALSE NEGATIVES FOUND!"
else
  false_negatives.sort.each_with_index do |test, idx|
    puts "#{idx + 1}. #{test}"
  end
end

# Common failures
common_failures = dom_failures & semantic_failures

puts
puts "=" * 80
puts "COMMON FAILURES (#{common_failures.size})"
puts "Tests that FAIL with BOTH algorithms:"
puts "=" * 80
puts "#{common_failures.size} tests fail with both algorithms"

# Summary
puts
puts "=" * 80
puts "SUMMARY"
puts "=" * 80
puts "Total tests:        #{dom_results['examples'].size}"
puts "DOM failures:       #{dom_failures.size}"
puts "Semantic failures:  #{semantic_failures.size}"
puts "Common failures:    #{common_failures.size}"
puts "False positives:    #{false_positives.size} (semantic fails, DOM passes)"
puts "False negatives:    #{false_negatives.size} (DOM fails, semantic passes)"
puts "Gap:                #{(semantic_failures.size - dom_failures.size).abs}"
puts "=" * 80
