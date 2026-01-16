#!/usr/bin/env ruby
# frozen_string_literal: true

# Direct comparison of current semantic vs DOM failures
# Usage: ruby scripts/compare_current_failures.rb

require "set"

def parse_failures(file)
  failures = Set.new
  File.readlines(file).each do |line|
    # Format: "rspec ./spec/isodoc/blocks_notes_spec.rb:494 # ..."
    if line =~ %r{rspec \./spec/isodoc/([a-z_0-9]+_spec\.rb):(\d+)}
      failures << "#{$1}:#{$2}"
    end
  end
  failures
end

semantic_file = "/tmp/semantic_fresh.txt"
dom_file = "/tmp/dom_fresh.txt"

puts "Parsing failures..."
semantic = parse_failures(semantic_file)
dom = parse_failures(dom_file)

puts "\n#{'=' * 80}"
puts "CURRENT FAILURE STATE"
puts "=" * 80

puts "\nTotal failures:"
puts "  Semantic: #{semantic.size}"
puts "  DOM:      #{dom.size}"
puts "  Gap:      #{(semantic.size - dom.size).abs}"

false_positives = semantic - dom # Semantic fails, DOM passes
false_negatives = dom - semantic   # DOM fails, Semantic passes
common = semantic & dom            # Both fail

puts "\n#{'-' * 80}"
puts "FALSE POSITIVES (Semantic fails, DOM passes): #{false_positives.size}"
puts "-" * 80
false_positives.sort.each { |f| puts "  #{f}" }

puts "\n#{'-' * 80}"
puts "FALSE NEGATIVES (DOM fails, Semantic passes): #{false_negatives.size}"
puts "-" * 80
false_negatives.sort.each { |f| puts "  #{f}" }

puts "\n#{'-' * 80}"
puts "COMMON FAILURES (Both fail): #{common.size}"
puts "-" * 80
puts "(Not listing #{common.size} common failures for brevity)"

puts "\n#{'=' * 80}"
puts "ANALYSIS"
puts "=" * 80

if false_positives.empty? && false_negatives.size == 1
  puts "\n✅ PERFECT PARITY ACHIEVED!"
  puts "  - No false positives (semantic not too strict)"
  puts "  - Only 1 false negative (acceptable difference)"
  puts "  - This is the target state!"
elsif false_positives.empty? && false_negatives.empty?
  puts "\n🎉 EXACT PARITY ACHIEVED!"
  puts "  - Both algorithms have identical failures"
  puts "  - #{common.size} common failures"
elsif false_positives.size == 1 && false_negatives.empty?
  puts "\n⚠️  ONE FALSE POSITIVE AWAY FROM PARITY"
  puts "  - Need to fix 1 case where semantic is too strict"
  puts "  - Target: #{dom.size} failures for both algorithms"
else
  puts "\n📊 Current Status:"
  puts "  - #{false_positives.size} false positives to fix (semantic too strict)"
  puts "  - #{false_negatives.size} false negatives to address (semantic too lenient)"
  puts "  - Gap from DOM: #{(semantic.size - dom.size).abs} failures"
end

# Save detailed results
output_file = "/tmp/current_failure_analysis.txt"
File.open(output_file, "w") do |f|
  f.puts "CURRENT FAILURE ANALYSIS"
  f.puts "=" * 80
  f.puts "\nSemantic: #{semantic.size} failures"
  f.puts "DOM:      #{dom.size} failures"
  f.puts "Gap:      #{(semantic.size - dom.size).abs}"
  f.puts "\nFALSE POSITIVES (#{false_positives.size}):"
  false_positives.sort.each { |fp| f.puts fp }
  f.puts "\nFALSE NEGATIVES (#{false_negatives.size}):"
  false_negatives.sort.each { |fn| f.puts fn }
  f.puts "\nCOMMON FAILURES (#{common.size}):"
  common.sort.each { |cf| f.puts cf }
end

puts "\nDetailed results saved to: #{output_file}"
