#!/usr/bin/env ruby
# frozen_string_literal: true

# Investigation script for the remaining 16 semantic vs DOM differences
# Goal: Achieve DOM parity (43 → 39 failures)

require "bundler/setup"
require "canon"

# The 16 test cases that fail with semantic but pass with DOM
REMAINING_FAILURES = [
  { file: "blocks_spec.rb", line: 352, category: "Whitespace in <pre>" },
  { file: "footnotes_spec.rb", line: 740, category: "Element matching" },
  { file: "inline_spec.rb", line: 1012, category: "Element matching" },
  { file: "inline_spec.rb", line: 1251, category: "Element matching" },
  { file: "postproc_spec.rb", line: 948, category: "HTML escapes" },
  { file: "postproc_word_spec.rb", line: 372, category: "Word processing" },
  { file: "postproc_word_spec.rb", line: 576, category: "Word processing" },
  { file: "presentation_xml_numbers_override_spec.rb", line: 2095,
    category: "Number formatting" },
  { file: "presentation_xml_spec.rb", line: 1288, category: "Presentation" },
  { file: "presentation_xml_spec.rb", line: 1500, category: "Presentation" },
  { file: "ref_spec.rb", line: 906, category: "References" },
  { file: "sourcecode_spec.rb", line: 124, category: "Sourcecode" },
  { file: "sourcecode_spec.rb", line: 610, category: "Sourcecode" },
  { file: "terms_spec.rb", line: 1445, category: "Terms" },
  { file: "xref_format_spec.rb", line: 628, category: "Cross-references" },
  { file: "xref_spec.rb", line: 315, category: "Cross-references" },
].freeze

class FailureInvestigator
  def initialize(test_case)
    @test_case = test_case
    @spec_file = File.join(ENV["HOME"], "mn/isodoc/spec", test_case[:file])
  end

  def investigate
    puts "\n#{'=' * 80}"
    puts "Investigating: #{@test_case[:file]}:#{@test_case[:line]}"
    puts "Category: #{@test_case[:category]}"
    puts "=" * 80

    extract_test_context
    analyze_failure_mode
    suggest_fix
  end

  private

  def extract_test_context
    puts "\n--- Test Context ---"

    unless File.exist?(@spec_file)
      puts "ERROR: Spec file not found: #{@spec_file}"
      return
    end

    lines = File.readlines(@spec_file)
    target_line = @test_case[:line] - 1

    # Find the test block
    start_line = target_line
    while start_line.positive? && !lines[start_line].strip.start_with?("it ",
                                                                       "specify ")
      start_line -= 1
    end

    # Extract test name
    test_name = lines[start_line].strip if start_line >= 0
    puts "Test: #{test_name}"

    # Show context around the assertion
    context_start = [target_line - 5, 0].max
    context_end = [target_line + 5, lines.length - 1].min

    puts "\nContext (lines #{context_start + 1}-#{context_end + 1}):"
    (context_start..context_end).each do |i|
      marker = i == target_line ? ">>>" : "   "
      puts "#{marker} #{i + 1}: #{lines[i].rstrip}"
    end
  end

  def analyze_failure_mode
    puts "\n--- Failure Analysis ---"

    case @test_case[:category]
    when "Whitespace in <pre>"
      puts "Pattern: Whitespace handling in <pre> elements"
      puts "Known issue: Semantic correctly detects whitespace differences"
      puts "DOM behavior: May normalize whitespace incorrectly"
      puts "Action needed: Verify if DOM is wrong or test expectations need adjustment"

    when "Element matching"
      puts "Pattern: Element matching/comparison issues"
      puts "Possible causes:"
      puts "  - Attribute ordering differences"
      puts "  - Namespace handling"
      puts "  - Element signature computation"
      puts "Action needed: Check signature and matching logic"

    when "HTML escapes"
      puts "Pattern: HTML entity/escape handling"
      puts "Possible causes:"
      puts "  - Entity normalization differences"
      puts "  - Character reference handling"
      puts "Action needed: Check entity handling in adapters"

    when "Word processing"
      puts "Pattern: Word-specific HTML processing"
      puts "Possible causes:"
      puts "  - Word-specific markup handling"
      puts "  - Style attribute differences"
      puts "Action needed: Check Word HTML adapter behavior"

    when "Number formatting", "Presentation"
      puts "Pattern: XML presentation/formatting"
      puts "Possible causes:"
      puts "  - Number/formatting element handling"
      puts "  - Presentation attribute differences"
      puts "Action needed: Check XML adapter presentation logic"

    when "References", "Cross-references"
      puts "Pattern: Reference/cross-reference handling"
      puts "Possible causes:"
      puts "  - Reference ID matching"
      puts "  - Link element comparison"
      puts "Action needed: Check reference element signatures"

    when "Sourcecode"
      puts "Pattern: Source code block handling"
      puts "Possible causes:"
      puts "  - Whitespace in code blocks (like <pre>)"
      puts "  - Code element attribute matching"
      puts "Action needed: Check sourcecode element handling"

    when "Terms"
      puts "Pattern: Term definition handling"
      puts "Possible causes:"
      puts "  - Term element matching"
      puts "  - Definition structure differences"
      puts "Action needed: Check term element signatures"
    end
  end

  def suggest_fix
    puts "\n--- Suggested Investigation Steps ---"
    puts "1. Run the specific test with both DOM and semantic:"
    puts "   cd ~/mn/isodoc"
    puts "   CANON_DIFF_MODE=dom bundle exec rspec #{@test_case[:file]}:#{@test_case[:line]}"
    puts "   CANON_DIFF_MODE=semantic_tree bundle exec rspec #{@test_case[:file]}:#{@test_case[:line]}"

    puts "\n2. If test fails with semantic, extract actual vs expected:"
    puts "   - Look for be_equivalent_to matcher"
    puts "   - Save actual and expected to temp files"
    puts "   - Compare manually"

    puts "\n3. Determine root cause:"
    puts "   - Is semantic detecting a real difference? → Test may need adjustment"
    puts "   - Is semantic wrongly flagging? → Bug in semantic algorithm"
    puts "   - Is DOM wrongly passing? → DOM has a bug we're fixing"

    puts "\n4. Check ROOT_CAUSE_ANALYSIS.md for similar patterns"
  end
end

# Main execution
puts "Investigating 16 Remaining Semantic vs DOM Differences"
puts "Goal: Achieve DOM parity (43 → 39 failures)"
puts "\nTotal cases to investigate: #{REMAINING_FAILURES.length}"

if ARGV.empty?
  puts "\nUsage:"
  puts "  #{$0}                    # Show all cases"
  puts "  #{$0} <number>           # Investigate specific case (1-#{REMAINING_FAILURES.length})"
  puts "  #{$0} <category>         # Investigate all cases in category"
  puts "\nAvailable categories:"
  REMAINING_FAILURES.map do |t|
    t[:category]
  end.uniq.sort.each { |c| puts "  - #{c}" }

  puts "\nAll cases:"
  REMAINING_FAILURES.each_with_index do |test, idx|
    puts "  #{idx + 1}. #{test[:file]}:#{test[:line]} - #{test[:category]}"
  end
else
  arg = ARGV[0]

  if /^\d+$/.match?(arg)
    # Specific case number
    idx = arg.to_i - 1
    if idx >= 0 && idx < REMAINING_FAILURES.length
      investigator = FailureInvestigator.new(REMAINING_FAILURES[idx])
      investigator.investigate
    else
      puts "ERROR: Invalid case number. Must be 1-#{REMAINING_FAILURES.length}"
    end
  else
    # Category filter
    category = arg
    matching = REMAINING_FAILURES.select do |t|
      t[:category].downcase.include?(category.downcase)
    end

    if matching.empty?
      puts "ERROR: No cases found for category: #{category}"
    else
      puts "\nInvestigating #{matching.length} cases matching '#{category}':"
      matching.each do |test|
        investigator = FailureInvestigator.new(test)
        investigator.investigate
      end
    end
  end
end
