#!/usr/bin/env ruby
# frozen_string_literal: true

# Investigate the 43 common failures to determine if they represent Canon classification bugs
# Both DOM and semantic algorithms agree these tests fail, but they might BOTH be wrong

require "json"
require "fileutils"

# Sample tests from the 43 common failures
SAMPLE_TESTS = [
  { file: "blocks_notes_spec.rb", line: 494 },
  { file: "blocks_provisions_spec.rb", line: 4 },
  { file: "cleanup_spec.rb", line: 180 },
  { file: "figures_spec.rb", line: 5 },
  { file: "tables_spec.rb", line: 4 },
  # Add more samples for thorough investigation
  { file: "blocks_notes_spec.rb", line: 12 },
  { file: "blocks_notes_spec.rb", line: 15 },
  { file: "blocks_notes_spec.rb", line: 18 },
  { file: "blocks_notes_spec.rb", line: 21 },
  { file: "cleanup_spec.rb", line: 126 },
].freeze

ISODOC_PATH = "/Users/mulgogi/src/mn/isodoc"
OUTPUT_DIR = "/tmp/common_failure_investigation"
FileUtils.mkdir_p(OUTPUT_DIR)

class CommonFailureInvestigator
  def initialize
    @findings = []
    @bugs_found = []
  end

  def investigate_all
    puts "=" * 80
    puts "INVESTIGATING 43 COMMON FAILURES"
    puts "Hypothesis: Both algorithms might incorrectly classify differences"
    puts "=" * 80
    puts

    SAMPLE_TESTS.each_with_index do |test, idx|
      puts "\n#{'-' * 80}"
      puts "Test #{idx + 1}/#{SAMPLE_TESTS.size}: #{test[:file]}:#{test[:line]}"
      puts "-" * 80

      investigate_test(test)
    end

    generate_report
  end

  private

  def investigate_test(test)
    spec_file = "spec/isodoc/#{test[:file]}"
    line = test[:line]

    # Run with DOM algorithm first
    puts "\n1. Running with DOM algorithm (verbose)..."
    dom_result = run_test_verbose(spec_file, line, "dom")

    # Run with Semantic algorithm
    puts "\n2. Running with Semantic algorithm (verbose)..."
    semantic_result = run_test_verbose(spec_file, line, "semantic")

    # Analyze both results
    finding = analyze_results(test, dom_result, semantic_result)
    @findings << finding

    if finding[:bug_suspected]
      @bugs_found << finding
      puts "\n⚠️  POTENTIAL BUG FOUND!"
      puts "   #{finding[:bug_description]}"
    else
      puts "\n✓ Classification appears correct"
    end
  end

  def run_test_verbose(spec_file, line, algorithm)
    output_file = "#{OUTPUT_DIR}/#{algorithm}_#{spec_file.gsub('/',
                                                               '_')}_#{line}.txt"

    cmd = <<~CMD
      cd #{ISODOC_PATH} && \
      CANON_ALGORITHM=#{algorithm} \
      CANON_VERBOSE=true \
      bundle exec rspec #{spec_file}:#{line} 2>&1 | tee #{output_file}
    CMD

    system(cmd)

    parse_test_output(output_file)
  end

  def parse_test_output(file)
    return nil unless File.exist?(file)

    content = File.read(file)

    {
      passed: content.include?("0 failures"),
      differences: extract_differences(content),
      match_options: extract_match_options(content),
      dimensions: extract_dimensions(content),
      raw_output: content,
    }
  end

  def extract_differences(content)
    diffs = []
    current_diff = nil

    content.each_line do |line|
      if line =~ /DIFFERENCE #(\d+):/
        current_diff = { number: $1.to_i, lines: [line] }
        diffs << current_diff
      elsif current_diff && line =~ /^\s*[│┌└├]/
        current_diff[:lines] << line
      elsif current_diff && line.strip.empty?
        current_diff = nil
      elsif current_diff
        current_diff[:lines] << line
      end
    end

    diffs
  end

  def extract_match_options(content)
    options = {}

    if content =~ /Match Options:\s*\{([^}]+)\}/
      options_str = $1
      options_str.scan(/(\w+):\s*:?(\w+)/) do |key, value|
        options[key.to_sym] = value.to_sym
      end
    end

    options
  end

  def extract_dimensions(content)
    dimensions = []

    content.scan(/Dimension:\s*(\w+)/) do |match|
      dimensions << match[0]
    end

    dimensions.uniq
  end

  def analyze_results(test, dom_result, semantic_result)
    finding = {
      test: test,
      bug_suspected: false,
      bug_description: nil,
      dom_analysis: analyze_single_result(dom_result),
      semantic_analysis: analyze_single_result(semantic_result),
    }

    # Check for classification bugs
    bugs = check_for_bugs(dom_result, semantic_result)
    if bugs.any?
      finding[:bug_suspected] = true
      finding[:bug_description] = bugs.join("; ")
    end

    finding
  end

  def analyze_single_result(result)
    return nil unless result

    {
      passed: result[:passed],
      match_options: result[:match_options],
      dimensions: result[:dimensions],
      diff_count: result[:differences].size,
    }
  end

  def check_for_bugs(dom_result, semantic_result)
    bugs = []

    return bugs unless dom_result && semantic_result

    # Check DOM result for bugs
    bugs.concat(check_result_for_bugs(dom_result, "DOM"))

    # Check Semantic result for bugs
    bugs.concat(check_result_for_bugs(semantic_result, "Semantic"))

    bugs
  end

  def check_result_for_bugs(result, algorithm)
    bugs = []
    return bugs if result[:passed]

    options = result[:match_options]
    dimensions = result[:dimensions]

    # Bug 1: attribute_order: ignore but order diffs are NORMATIVE
    if options[:attribute_order] == :ignore && dimensions.include?("attribute_order")
      bugs << "#{algorithm}: attribute_order:ignore but order diffs reported as NORMATIVE"
    end

    # Bug 2: text_content normalization issues
    if options[:text_content] == :normalize && dimensions.include?("text_content")
      # Check if the diff is about normalized-equivalent text
      result[:differences].each do |diff|
        diff_text = diff[:lines].join
        if diff_text.include?("whitespace") || diff_text.include?("spacing")
          bugs << "#{algorithm}: text_content:normalize but whitespace diffs reported"
        end
      end
    end

    # Bug 3: comments: ignore but comments cause failure
    if options[:comments] == :ignore && dimensions.include?("comment")
      bugs << "#{algorithm}: comments:ignore but comment diffs reported as NORMATIVE"
    end

    # Bug 4: whitespace_only: ignore but whitespace-only changes fail
    if options[:whitespace_only] == :ignore
      result[:differences].each do |diff|
        diff_text = diff[:lines].join
        if diff_text.match?(/only.*whitespace/i)
          bugs << "#{algorithm}: whitespace_only:ignore but whitespace-only diffs reported"
        end
      end
    end

    bugs
  end

  def generate_report
    report_file = "#{OUTPUT_DIR}/CLASSIFICATION_INVESTIGATION_REPORT.md"

    File.open(report_file, "w") do |f|
      f.puts "# Classification Investigation Report"
      f.puts
      f.puts "Investigation of the 43 common failures where both DOM and semantic algorithms agree."
      f.puts
      f.puts "**Date:** #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
      f.puts
      f.puts "## Executive Summary"
      f.puts
      f.puts "- Tests investigated: #{@findings.size}"
      f.puts "- Potential bugs found: #{@bugs_found.size}"
      f.puts

      if @bugs_found.any?
        f.puts "## ⚠️ Bugs Found"
        f.puts
        @bugs_found.each_with_index do |bug, idx|
          f.puts "### Bug #{idx + 1}: #{bug[:test][:file]}:#{bug[:test][:line]}"
          f.puts
          f.puts "**Description:** #{bug[:bug_description]}"
          f.puts
          f.puts "**DOM Analysis:**"
          f.puts "```"
          f.puts bug[:dom_analysis].inspect
          f.puts "```"
          f.puts
          f.puts "**Semantic Analysis:**"
          f.puts "```"
          f.puts bug[:semantic_analysis].inspect
          f.puts "```"
          f.puts
        end
      else
        f.puts "## ✅ No Classification Bugs Found"
        f.puts
        f.puts "All investigated failures appear to be legitimate test failures,"
        f.puts "not bugs in Canon's classification logic."
        f.puts
      end

      f.puts "## Detailed Findings"
      f.puts
      @findings.each_with_index do |finding, idx|
        f.puts "### Test #{idx + 1}: #{finding[:test][:file]}:#{finding[:test][:line]}"
        f.puts
        f.puts "**Bug Suspected:** #{finding[:bug_suspected] ? 'YES ⚠️' : 'No'}"
        f.puts
        if finding[:bug_description]
          f.puts "**Issue:** #{finding[:bug_description]}"
          f.puts
        end
        f.puts "**DOM:**"
        f.puts "- Match Options: #{finding[:dom_analysis][:match_options]}"
        f.puts "- Dimensions: #{finding[:dom_analysis][:dimensions].join(', ')}"
        f.puts "- Diff Count: #{finding[:dom_analysis][:diff_count]}"
        f.puts
        f.puts "**Semantic:**"
        f.puts "- Match Options: #{finding[:semantic_analysis][:match_options]}"
        f.puts "- Dimensions: #{finding[:semantic_analysis][:dimensions].join(', ')}"
        f.puts "- Diff Count: #{finding[:semantic_analysis][:diff_count]}"
        f.puts
        f.puts "---"
        f.puts
      end

      f.puts "## Next Steps"
      f.puts
      if @bugs_found.any?
        f.puts "1. Review the bugs found above"
        f.puts "2. Fix classification logic in:"
        f.puts "   - `lib/canon/diff/diff_classifier.rb`"
        f.puts "   - `lib/canon/tree_diff/operation_converter.rb`"
        f.puts "3. Re-run tests to verify fixes"
      else
        f.puts "The 43 common failures appear to be legitimate test failures,"
        f.puts "not Canon classification bugs. These tests fail correctly in both algorithms."
      end
    end

    puts "\n\n#{'=' * 80}"
    puts "INVESTIGATION COMPLETE"
    puts "=" * 80
    puts
    puts "Report saved to: #{report_file}"
    puts
    puts "Summary:"
    puts "  Tests investigated: #{@findings.size}"
    puts "  Bugs found: #{@bugs_found.size}"
    puts

    if @bugs_found.any?
      puts "⚠️  Classification bugs detected! See report for details."
    else
      puts "✓ No classification bugs found. Failures are legitimate."
    end
    puts
  end
end

# Run investigation
investigator = CommonFailureInvestigator.new
investigator.investigate_all
