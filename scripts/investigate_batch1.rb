#!/usr/bin/env ruby
# frozen_string_literal: true

# Investigate first batch of false positives in detail

ISODOC_DIR = File.expand_path("../../../mn/isodoc", __dir__)

BATCH_1 = [
  { file: "spec/isodoc/blocks_spec.rb", line: 352 },
  { file: "spec/isodoc/footnotes_spec.rb", line: 740 },
  { file: "spec/isodoc/inline_spec.rb", line: 1012 },
  { file: "spec/isodoc/inline_spec.rb", line: 1251 },
  { file: "spec/isodoc/postproc_spec.rb", line: 948 },
].freeze

def run_test(test, algorithm)
  file = File.join(ISODOC_DIR, test[:file])
  cmd = "cd #{ISODOC_DIR} && CANON_ALGORITHM=#{algorithm} bundle exec rspec #{file}:#{test[:line]} 2>&1"
  output = `#{cmd}`
  success = $?.success?

  {
    success: success,
    output: output,
  }
end

def extract_diff(output)
  lines = output.lines

  # Find the diff section
  diff_start = lines.index { |l| l.include?("Diff:") }
  return nil unless diff_start

  # Extract lines after "Diff:" until we hit a blank line or end
  diff_lines = []
  (diff_start + 1...lines.size).each do |i|
    line = lines[i]
    break if line.strip.empty? && diff_lines.size > 5

    diff_lines << line
  end

  diff_lines.join
end

def analyze_diff(diff)
  return {} unless diff

  analysis = {
    whitespace: diff.match?(/\s+/) && diff.match?(/^\s*[-+]/),
    attributes: diff.match?(/\sattr|attribute/i),
    text_content: diff.match?(/text|content/i),
    elements: diff.match?(/element|tag|node/i),
    line_count: diff.lines.size,
  }

  # Sample key differences
  added = diff.lines.select do |l|
    l.start_with?("+") && !l.start_with?("+++")
  end.take(3)
  removed = diff.lines.select do |l|
    l.start_with?("-") && !l.start_with?("---")
  end.take(3)

  analysis[:sample_added] = added
  analysis[:sample_removed] = removed
  analysis
end

puts "=" * 80
puts "BATCH 1 INVESTIGATION: 5 False Positives"
puts "=" * 80
puts

BATCH_1.each_with_index do |test, idx|
  puts "\n#{idx + 1}/5: #{test[:file].sub('spec/isodoc/', '')}:#{test[:line]}"
  puts "-" * 80

  # Run with semantic (should fail)
  sem_result = run_test(test, "semantic")

  if sem_result[:success]
    puts "⚠️  UNEXPECTED: Test passes with semantic (may have been fixed)"
    next
  end

  puts "✓ Confirmed: Fails with semantic as expected"

  # Extract and analyze diff
  diff = extract_diff(sem_result[:output])

  if diff
    puts "\n📊 Diff Analysis:"
    analysis = analyze_diff(diff)

    puts "  Diff size: #{analysis[:line_count]} lines"
    puts "  Involves whitespace: #{analysis[:whitespace]}" if analysis[:whitespace]
    puts "  Involves attributes: #{analysis[:attributes]}" if analysis[:attributes]
    puts "  Involves text content: #{analysis[:text_content]}" if analysis[:text_content]
    puts "  Involves elements: #{analysis[:elements]}" if analysis[:elements]

    if analysis[:sample_removed].any?
      puts "\n  Sample lines REMOVED (semantic sees but DOM doesn't):"
      analysis[:sample_removed].each { |l| puts "    #{l.strip}" }
    end

    if analysis[:sample_added].any?
      puts "\n  Sample lines ADDED (semantic missing but DOM has):"
      analysis[:sample_added].each { |l| puts "    #{l.strip}" }
    end

    # Show first 30 lines of actual diff
    puts "\n  📋 First 30 lines of diff:"
    diff.lines.take(30).each do |line|
      puts "    #{line.rstrip}"
    end
  else
    puts "\n⚠️  Could not extract diff from output"
    puts "\nFirst 50 lines of output:"
    sem_result[:output].lines.take(50).each { |l| puts "  #{l.rstrip}" }
  end
end

puts "\n#{'=' * 80}"
puts "BATCH 1 INVESTIGATION COMPLETE"
puts "=" * 80
