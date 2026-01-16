#!/usr/bin/env ruby
# frozen_string_literal: true

# Analyze false positive patterns to identify systematic issues
# Usage: ruby scripts/analyze_false_positives.rb /tmp/semantic_failures_final.txt

require "json"

# Parse false positives from comparison results
def parse_false_positives
  file = "/tmp/failure_comparison.txt"
  false_positives = []
  in_section = false

  File.readlines(file).each do |line|
    if line.include?("FALSE POSITIVES")
      in_section = true
      next
    elsif line.include?("FALSE NEGATIVES")
      break
    end

    next unless in_section
    next if line.strip.empty?

    # Parse line like "blocks_spec.rb:352"
    if line =~ /^\s*([a-z_]+_spec\.rb):(\d+)/
      false_positives << { file: $1, line: $2.to_i }
    end
  end

  false_positives
end

# Run a specific test to capture its output
def run_test(spec_file, line_num)
  cmd = "cd /Users/mulgogi/src/mn/isodoc && CANON_ALGORITHM=semantic bundle exec rspec ./spec/isodoc/#{spec_file}:#{line_num} 2>&1"
  output = `#{cmd}`

  {
    spec: "#{spec_file}:#{line_num}",
    output: output,
    has_diff: output.include?("expected"),
    diff_preview: extract_diff_preview(output),
  }
end

def extract_diff_preview(output)
  lines = output.lines
  diff_start = lines.index { |l| l.include?("expected") || l.include?("Diff:") }
  return nil unless diff_start

  # Get 10 lines after the diff marker
  preview = lines[diff_start, 10].join
  preview.length > 500 ? "#{preview[0..500]}..." : preview
end

def main
  puts "Analyzing false positive patterns..."
  puts "=" * 80

  false_positives = parse_false_positives
  puts "\nFound #{false_positives.size} false positives to analyze"

  # Group by spec file
  by_file = false_positives.group_by { |fp| fp[:file] }

  puts "\nBreakdown by file:"
  by_file.sort_by { |_, v| -v.size }.each do |file, items|
    puts "  #{file}: #{items.size} failures"
  end

  # Sample a few from each top category
  puts "\n#{'=' * 80}"
  puts "SAMPLING TOP FAILURES FOR PATTERN ANALYSIS"
  puts "=" * 80

  samples = []

  # Take first 2 from each top category
  by_file.sort_by { |_, v| -v.size }.take(5).each_value do |items|
    items.take(2).each do |item|
      puts "\n#{'-' * 80}"
      puts "Testing: #{item[:file]}:#{item[:line]}"
      puts "-" * 80

      result = run_test(item[:file], item[:line])
      samples << result

      if result[:has_diff]
        puts "\nDiff Preview:"
        puts result[:diff_preview]
      else
        puts "\nNo diff found in output"
      end
    end
  end

  # Save results
  output = {
    total_false_positives: false_positives.size,
    by_file: by_file.transform_values(&:size),
    samples: samples.map do |s|
      { spec: s[:spec], diff_preview: s[:diff_preview] }
    end,
  }

  File.write("/tmp/false_positive_analysis.json", JSON.pretty_generate(output))
  puts "\n#{'=' * 80}"
  puts "Analysis saved to /tmp/false_positive_analysis.json"
  puts "=" * 80
end

main if __FILE__ == $PROGRAM_NAME
