#!/usr/bin/env ruby
# frozen_string_literal: true

# Test all 16 false positives with both algorithms
# Usage: ruby scripts/test_all_false_positives.rb

FALSE_POSITIVES = [
  "spec/isodoc/blocks_spec.rb:352",
  "spec/isodoc/footnotes_spec.rb:740",
  "spec/isodoc/inline_spec.rb:1012",
  "spec/isodoc/inline_spec.rb:1251",
  "spec/isodoc/postproc_spec.rb:948",
  "spec/isodoc/postproc_word_spec.rb:372",
  "spec/isodoc/postproc_word_spec.rb:576",
  "spec/isodoc/presentation_xml_numbers_override_spec.rb:2095",
  "spec/isodoc/presentation_xml_spec.rb:1288",
  "spec/isodoc/presentation_xml_spec.rb:1500",
  "spec/isodoc/ref_spec.rb:906",
  "spec/isodoc/sourcecode_spec.rb:124",
  "spec/isodoc/sourcecode_spec.rb:610",
  "spec/isodoc/terms_spec.rb:1445",
  "spec/isodoc/xref_format_spec.rb:628",
  "spec/isodoc/xref_spec.rb:315",
].freeze

ISODOC_DIR = "/Users/mulgogi/src/mn/isodoc"

results = {}

puts "=" * 80
puts "TESTING ALL 16 FALSE POSITIVES"
puts "=" * 80
puts

FALSE_POSITIVES.each_with_index do |test, idx|
  puts "\n#{idx + 1}. Testing: #{test}"
  puts "-" * 60

  # Test with DOM
  ENV["CANON_HTML_DIFF_ALGORITHM"] = "dom"
  ENV["CANON_XML_DIFF_ALGORITHM"] = "dom"
  `cd #{ISODOC_DIR} && bundle exec rspec #{test} 2>&1`
  dom_pass = $?.success?

  # Test with Semantic
  ENV["CANON_HTML_DIFF_ALGORITHM"] = "semantic"
  ENV["CANON_XML_DIFF_ALGORITHM"] = "semantic"
  `cd #{ISODOC_DIR} && bundle exec rspec #{test} 2>&1`
  semantic_pass = $?.success?

  results[test] = {
    dom: dom_pass,
    semantic: semantic_pass,
    false_positive: dom_pass && !semantic_pass,
  }

  status = if dom_pass && !semantic_pass
             "❌ FALSE POSITIVE (DOM pass, Semantic fail)"
           elsif !dom_pass && semantic_pass
             "⚠️  FALSE NEGATIVE (DOM fail, Semantic pass)"
           elsif dom_pass && semantic_pass
             "✅ BOTH PASS"
           else
             "⏺  BOTH FAIL"
           end

  puts "   #{status}"
end

# Summary
puts "\n#{'=' * 80}"
puts "SUMMARY"
puts "=" * 80

false_positives = results.select { |_, r| r[:false_positive] }
false_negatives = results.select { |_, r| !r[:dom] && r[:semantic] }
both_pass = results.select { |_, r| r[:dom] && r[:semantic] }
both_fail = results.select { |_, r| !r[:dom] && !r[:semantic] }

puts "\nFalse Positives (DOM pass, Semantic fail): #{false_positives.count}"
false_positives.each_key { |test| puts "  - #{test}" }

puts "\nFalse Negatives (DOM fail, Semantic pass): #{false_negatives.count}"
false_negatives.each_key { |test| puts "  - #{test}" }

puts "\nBoth Pass: #{both_pass.count}"
both_pass.each_key { |test| puts "  - #{test}" }

puts "\nBoth Fail: #{both_fail.count}"
both_fail.each_key { |test| puts "  - #{test}" }

puts "\n#{'=' * 80}"
puts "Current state: #{false_positives.count} false positives remaining"
puts "Target: 0 false positives (achieve DOM parity)"
puts "=" * 80
