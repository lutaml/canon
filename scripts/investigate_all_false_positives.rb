#!/usr/bin/env ruby
# frozen_string_literal: true

# Systematically investigate all false positive failures
# to identify patterns in why semantic fails but DOM passes

require "fileutils"

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

ISODOC_PATH = "/Users/mulgogi/src/mn/isodoc"

def run_test(spec_file, line, algorithm)
  cmd = "cd #{ISODOC_PATH} && CANON_ALGORITHM=#{algorithm} bundle exec rspec ./spec/isodoc/#{spec_file}:#{line} 2>&1"
  output = `#{cmd}`
  {
    passed: $?.success?,
    output: output,
  }
end

def extract_diff_type(output)
  # Look for dimension in diff report
  if output =~ /Dimension:[^\n]*\n[^\n]*Location:[^\n]*([^\n]+)/
    location = $1.strip
  end

  if output =~ /Dimension:\s*([^\n]+)/
    dimension = $1.strip
  end

  # Look for changes description
  changes = []
  output.scan(/✨ Changes:\s*([^\n]+)/) do |match|
    changes << match[0].strip
  end

  {
    dimension: dimension,
    location: location,
    changes: changes,
  }
end

def analyze_false_positive(fp)
  file, line = fp.split(":")
  puts "\n#{'=' * 80}"
  puts "Analyzing: #{fp}"
  puts "=" * 80

  # Run with both algorithms
  puts "\nRunning with DOM algorithm..."
  dom_result = run_test(file, line, "dom")

  puts "Running with SEMANTIC algorithm..."
  semantic_result = run_test(file, line, "semantic")

  # Verify it's actually a false positive
  unless dom_result[:passed] && !semantic_result[:passed]
    puts "⚠️  WARNING: Not a false positive!"
    puts "  DOM passed: #{dom_result[:passed]}"
    puts "  Semantic passed: #{semantic_result[:passed]}"
    return nil
  end

  puts "✓ Confirmed false positive (DOM passes, Semantic fails)"

  # Extract diff details from semantic output
  diff_info = extract_diff_type(semantic_result[:output])

  puts "\nDiff Details:"
  puts "  Dimension: #{diff_info[:dimension] || 'unknown'}"
  puts "  Location: #{diff_info[:location] || 'unknown'}"
  puts "  Changes: #{diff_info[:changes].join(', ')}" unless diff_info[:changes].empty?

  # Save full output for detailed analysis
  output_dir = "/tmp/false_positives"
  FileUtils.mkdir_p(output_dir)

  File.write("#{output_dir}/#{file.gsub('.rb', '')}_#{line}.txt",
             semantic_result[:output])
  puts "\nFull output saved to: #{output_dir}/#{file.gsub('.rb',
                                                          '')}_#{line}.txt"

  diff_info.merge(spec: fp, file: file, line: line)
end

def main
  puts "Investigating #{FALSE_POSITIVES.size} false positives..."
  puts "This will take several minutes..."

  results = []

  FALSE_POSITIVES.each_with_index do |fp, idx|
    puts "\n[#{idx + 1}/#{FALSE_POSITIVES.size}]"
    result = analyze_false_positive(fp)
    results << result if result
    sleep 0.5 # Brief pause between tests
  end

  # Summarize patterns
  puts "\n#{'=' * 80}"
  puts "PATTERN ANALYSIS"
  puts "=" * 80

  puts "\nBy Dimension:"
  dimension_groups = results.compact.group_by { |r| r[:dimension] }
  dimension_groups.each do |dim, group|
    puts "  #{dim}: #{group.size} cases"
    group.each { |r| puts "    - #{r[:spec]}" }
  end

  puts "\nBy Changes:"
  changes_groups = results.compact.group_by { |r| r[:changes].join(", ") }
  changes_groups.each do |change, group|
    puts "  #{change}: #{group.size} cases"
    group.each { |r| puts "    - #{r[:spec]}" }
  end

  # Save summary
  summary_file = "/tmp/false_positive_patterns.txt"
  File.open(summary_file, "w") do |f|
    f.puts "FALSE POSITIVE PATTERN ANALYSIS"
    f.puts "=" * 80
    f.puts "\nTotal: #{results.compact.size} false positives analyzed"

    f.puts "\n\nBy Dimension:"
    dimension_groups.each do |dim, group|
      f.puts "  #{dim}: #{group.size}"
      group.each { |r| f.puts "    #{r[:spec]}" }
    end

    f.puts "\n\nBy Changes:"
    changes_groups.each do |change, group|
      f.puts "  #{change}: #{group.size}"
      group.each { |r| f.puts "    #{r[:spec]}" }
    end
  end

  puts "\nSummary saved to: #{summary_file}"
  puts "\nDetailed outputs in: /tmp/false_positives/"
end

main if __FILE__ == $PROGRAM_NAME
