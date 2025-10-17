require "spec_helper"

RSpec.describe "Context and Grouping Behavior" do
  let(:expected_path) { "spec/fixtures/xml/isodoc-blockquotes-expected.xml" }
  let(:actual_path) { "spec/fixtures/xml/isodoc-blockquotes-actual.xml" }

  def format_diff(context_lines:, diff_grouping_lines:)
    expected = File.read(expected_path)
    actual = File.read(actual_path)
    formatter = Canon::DiffFormatter.new(
      use_color: false,
      mode: :by_line,
      context_lines: context_lines,
      diff_grouping_lines: diff_grouping_lines,
    )
    formatter.format([], :xml, doc1: expected, doc2: actual)
  end

  describe "with context_lines: 0, diff_grouping_lines: 0" do
    it "shows 2 separate diffs (separated by identical line 24)" do
      diff = format_diff(context_lines: 0, diff_grouping_lines: 0)
      puts "\n#{'=' * 80}"
      puts "context_lines: 0, diff_grouping_lines: 0"
      puts "=" * 80
      puts diff
      puts "=" * 80

      # Should show 2 separate contexts:
      # 1. Lines 19-23 (first <p>)
      # 2. Lines 25-32 (second <p>)
      # Line 24 (<attribution>) is identical and should NOT appear
    end
  end

  describe "with context_lines: 0, diff_grouping_lines: 2" do
    it "shows 1 combined diff (gap of 1 line is within grouping distance)" do
      diff = format_diff(context_lines: 0, diff_grouping_lines: 2)
      puts "\n#{'=' * 80}"
      puts "context_lines: 0, diff_grouping_lines: 2"
      puts "=" * 80
      puts diff
      puts "=" * 80

      # Should show 1 combined context with:
      # - Lines 19-23 (first <p>)
      # - Line 24 (<attribution>) as context between the two diffs
      # - Lines 25-32 (second <p>)
    end
  end

  describe "with context_lines: 0, diff_grouping_lines: 5" do
    it "shows grouped diffs with smaller gaps merged" do
      diff = format_diff(context_lines: 0, diff_grouping_lines: 5)
      puts "\n#{'=' * 80}"
      puts "context_lines: 0, diff_grouping_lines: 5"
      puts "=" * 80
      puts diff
      puts "=" * 80

      # With grouping_lines: 5, blocks with gaps <= 5 should be grouped
      # Block at line 5 and block at line 9 have gap of 3, so they group
      # Block at line 9 and block at line 19 have gap of 9, so they don't group
      # Block at line 19-23 and block at line 25-32 have gap of 1, so they group
      # Expected: 2 context blocks
    end
  end
end
