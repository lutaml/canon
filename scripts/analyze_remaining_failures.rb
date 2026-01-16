#!/usr/bin/env ruby
# frozen_string_literal: true

# Compare semantic tree failures vs DOM diff failures
# to identify remaining false positives

# DOM diff failures (39 - the baseline/correct)
dom_failures = [
  "blocks_notes_spec.rb:494",
  "blocks_provisions_spec.rb:4",
  "blocks_spec.rb:4",
  "blocks_spec.rb:1062",
  "cleanup_spec.rb:180",
  "cleanup_spec.rb:347",
  "figures_spec.rb:5",
  "figures_spec.rb:1662",
  "figures_spec.rb:1764",
  "figures_spec.rb:1815",
  "footnotes_spec.rb:5",
  "i18n_spec.rb:1644",
  "inline_spec.rb:610",
  "inline_spec.rb:726",
  "inline_spec.rb:2114",
  "lists_spec.rb:4",
  "lists_spec.rb:817",
  "postproc_spec.rb:1010",
  "postproc_spec.rb:1084",
  "postproc_word_spec.rb:89",
  "presentation_xml_metadata_spec.rb:75",
  "presentation_xml_spec.rb:454",
  "ref_identifier_spec.rb:446",
  "ref_identifier_spec.rb:602",
  "ref_identifier_spec.rb:671",
  "ref_identifier_spec.rb:872",
  "ref_spec.rb:4",
  "ref_spec.rb:1511",
  "ref_spec.rb:1705",
  "section_spec.rb:4",
  "section_spec.rb:736",
  "section_title_spec.rb:4",
  "sourcecode_spec.rb:4",
  "sourcecode_spec.rb:838",
  "table_debug_spec.rb:4",
  "table_spec.rb:4",
  "table_spec.rb:811",
  "table_spec.rb:1683",
  "table_spec.rb:1906",
].to_set

# Read semantic failures from file
semantic_failures = File.readlines("/tmp/semantic_failures.txt").map do |line|
  # Extract spec file and line number from rspec output
  if line =~ /rspec \.\/spec\/isodoc\/(.+?)# /
    $1.strip
  end
end.compact.to_set

puts "=" * 80
puts "SEMANTIC TREE ALGORITHM - ANALYSIS AFTER FIX"
puts "=" * 80
puts
puts "Statistics:"
puts "  DOM diff failures (baseline):     #{dom_failures.size}"
puts "  Semantic tree failures (current):  #{semantic_failures.size}"
puts "  False positives (semantic only):   #{(semantic_failures - dom_failures).size}"
puts "  False negatives (DOM only):        #{(dom_failures - semantic_failures).size}"
puts

# False positives (in semantic but not in DOM)
false_positives = semantic_failures - dom_failures
if false_positives.any?
  puts "FALSE POSITIVES (#{false_positives.size} remaining):"
  puts "-" * 80
  false_positives.sort.each do |failure|
    puts "  • #{failure}"
  end
  puts
end

# False negatives (in DOM but not in semantic)
false_negatives = dom_failures - semantic_failures
if false_negatives.any?
  puts "FALSE NEGATIVES (#{false_negatives.size} tests):"
  puts "-" * 80
  false_negatives.sort.each do |failure|
    puts "  • #{failure}"
  end
  puts
end

# Real failures (both agree)
real_failures = dom_failures & semantic_failures
puts "REAL FAILURES (#{real_failures.size} tests - both algorithms agree):"
puts "-" * 80
real_failures.sort.each do |failure|
  puts "  • #{failure}"
end
puts

puts "=" * 80
puts "SUMMARY:"
puts "  ✅ Fixed false positives: #{46 - false_positives.size} tests"
puts "  ⚠️  Remaining false positives: #{false_positives.size} tests"
puts "  ⚠️  False negatives: #{false_negatives.size} tests"
puts "=" * 80
