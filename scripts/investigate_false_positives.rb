#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to systematically investigate false positives
# where semantic algorithm fails but DOM algorithm passes

require "fileutils"
require "json"

# False positives to investigate
FALSE_POSITIVES = [
  { file: "blocks_spec.rb", line: 352 },
  { file: "footnotes_spec.rb", line: 740 },
  { file: "inline_spec.rb", line: 1012 },
  { file: "inline_spec.rb", line: 1251 },
  { file: "postproc_spec.rb", line: 948 },
  { file: "postproc_word_spec.rb", line: 372 },
  { file: "postproc_word_spec.rb", line: 576 },
  { file: "presentation_xml_numbers_override_spec.rb", line: 2095 },
  { file: "presentation_xml_spec.rb", line: 1288 },
  { file: "presentation_xml_spec.rb", line: 1500 },
  { file: "ref_spec.rb", line: 906 },
  { file: "sourcecode_spec.rb", line: 124 },
  { file: "sourcecode_spec.rb", line: 610 },
  { file: "terms_spec.rb", line: 1445 },
  { file: "xref_format_spec.rb", line: 628 },
  { file: "xref_spec.rb", line: 315 },
].freeze

ISODOC_SPEC_DIR = File.expand_path("../../../mn/isodoc/spec/isodoc", __dir__)

class FalsePositiveInvestigator
  attr_reader :results

  def initialize
    @results = []
  end

  def investigate_all
    puts "=" * 80
    puts "INVESTIGATING 16 FALSE POSITIVES"
    puts "=" * 80
    puts

    FALSE_POSITIVES.each_with_index do |test, idx|
      puts "\n#{idx + 1}/#{FALSE_POSITIVES.size}: #{test[:file]}:#{test[:line]}"
      puts "-" * 80

      result = investigate_test(test)
      @results << result

      display_result(result)
    end

    summarize_results
  end

  def investigate_test(test)
    file_path = File.join(ISODOC_SPEC_DIR, test[:file])

    unless File.exist?(file_path)
      return {
        test: test,
        error: "File not found: #{file_path}",
        dom_passes: nil,
        semantic_passes: nil,
      }
    end

    result = {
      test: test,
      file_path: file_path,
      dom_passes: nil,
      semantic_passes: nil,
      semantic_output: nil,
      error: nil,
    }

    # Test with DOM algorithm
    puts "  Testing with DOM algorithm..."
    dom_output = run_test(file_path, test[:line], "dom")
    result[:dom_passes] = dom_output[:success]
    result[:dom_output] = dom_output[:output]

    # Test with semantic algorithm
    puts "  Testing with semantic algorithm..."
    semantic_output = run_test(file_path, test[:line], "semantic")
    result[:semantic_passes] = semantic_output[:success]
    result[:semantic_output] = semantic_output[:output]

    result
  rescue StandardError => e
    {
      test: test,
      error: "Exception: #{e.message}",
      dom_passes: nil,
      semantic_passes: nil,
    }
  end

  def run_test(file_path, line, algorithm)
    cmd = "cd #{ISODOC_SPEC_DIR}/.. && CANON_ALGORITHM=#{algorithm} bundle exec rspec #{file_path}:#{line} 2>&1"
    output = `#{cmd}`
    success = $?.success?

    {
      success: success,
      output: output,
      exit_code: $?.exitstatus,
    }
  end

  def display_result(result)
    if result[:error]
      puts "  ❌ ERROR: #{result[:error]}"
      return
    end

    dom_status = result[:dom_passes] ? "✅ PASS" : "❌ FAIL"
    sem_status = result[:semantic_passes] ? "✅ PASS" : "❌ FAIL"

    puts "  DOM:      #{dom_status}"
    puts "  Semantic: #{sem_status}"

    if result[:dom_passes] && !result[:semantic_passes]
      puts "  ⚠️  CONFIRMED FALSE POSITIVE"
      analyze_failure(result)
    elsif !result[:dom_passes] && result[:semantic_passes]
      puts "  ⚠️  UNEXPECTED: DOM fails but semantic passes!"
    elsif !result[:dom_passes] && !result[:semantic_passes]
      puts "  ℹ️  Both algorithms fail (not a false positive)"
    else
      puts "  ✅ Both algorithms pass (false positive may be fixed)"
    end
  end

  def analyze_failure(result)
    output = result[:semantic_output]

    # Look for diff patterns
    if output.include?("Expected XML to be equivalent")
      puts "  📋 Failure type: XML equivalence check"
    elsif output.include?("Expected HTML to be equivalent")
      puts "  📋 Failure type: HTML equivalence check"
    end

    # Extract key diff lines
    diff_lines = output.lines.select { |l| l.match?(/^\s*[+-]/) }.take(10)
    if diff_lines.any?
      puts "  📊 Sample diff:"
      diff_lines.each { |l| puts "    #{l.strip}" }
    end

    # Look for specific patterns
    if output.include?("whitespace")
      puts "  🔍 Involves: whitespace differences"
    end
    if output.include?("attribute")
      puts "  🔍 Involves: attribute differences"
    end
    if output.include?("text content")
      puts "  🔍 Involves: text content differences"
    end
  end

  def summarize_results
    puts "\n#{'=' * 80}"
    puts "SUMMARY"
    puts "=" * 80

    confirmed_fps = @results.count do |r|
      r[:dom_passes] && !r[:semantic_passes]
    end
    fixed = @results.count { |r| r[:dom_passes] && r[:semantic_passes] }
    errors = @results.count { |r| r[:error] }
    both_fail = @results.count { |r| !r[:dom_passes] && !r[:semantic_passes] }

    puts "Confirmed false positives: #{confirmed_fps}/16"
    puts "Already fixed:             #{fixed}/16"
    puts "Both fail (not FP):        #{both_fail}/16"
    puts "Errors:                    #{errors}/16"
    puts

    if confirmed_fps.positive?
      puts "FALSE POSITIVES TO FIX:"
      @results.each do |r|
        next unless r[:dom_passes] && !r[:semantic_passes]

        puts "  - #{r[:test][:file]}:#{r[:test][:line]}"
      end
    end

    puts "\n#{'=' * 80}"
  end

  def save_detailed_output(output_dir = "tmp/false_positive_investigation")
    FileUtils.mkdir_p(output_dir)

    @results.each_with_index do |result, idx|
      next if result[:error]

      test = result[:test]
      filename = "#{idx + 1}_#{test[:file].gsub('.rb', '')}_#{test[:line]}.txt"
      filepath = File.join(output_dir, filename)

      File.write(filepath, <<~OUTPUT)
        Test: #{test[:file]}:#{test[:line]}
        DOM passes: #{result[:dom_passes]}
        Semantic passes: #{result[:semantic_passes]}

        ========================================
        SEMANTIC OUTPUT:
        ========================================
        #{result[:semantic_output]}
      OUTPUT
    end

    puts "\nDetailed output saved to: #{output_dir}/"
  end
end

# Run investigation
investigator = FalsePositiveInvestigator.new
investigator.investigate_all
investigator.save_detailed_output

puts "\nInvestigation complete!"
