require "spec_helper"

RSpec.describe "MECE XML Diff Scenarios" do
  let(:formatter) do
    Canon::DiffFormatter.new(use_color: false, mode: :by_line,
                            context_lines: 0, diff_grouping_lines: 10)
  end

  def format_diff(expected_path, actual_path)
    expected = File.read(expected_path)
    actual = File.read(actual_path)
    formatter.format([], :xml, doc1: expected, doc2: actual)
  end

  describe "Scenario 1: Single leaf change in single-line parent" do
    it "shows complete parent element when leaf changes" do
      expected_path = "spec/fixtures/xml/scenario1-single-leaf-single-line-parent-expected.xml"
      actual_path = "spec/fixtures/xml/scenario1-single-leaf-single-line-parent-actual.xml"

      diff = format_diff(expected_path, actual_path)
      puts "\n" + "="*80
      puts "SCENARIO 1: Single leaf change in single-line parent"
      puts "="*80
      puts diff
      puts "="*80

      # The diff should show:
      # - Line 5 with <bold>world</bold> (file 1)
      # + Line 5 with <em>world</em> (file 2)
      # The parent <text> element should be shown in full since it's on one line
    end
  end

  describe "Scenario 2: Single leaf change in multi-line parent" do
    it "shows only immediate parent with changes, trimming unchanged lines" do
      expected_path = "spec/fixtures/xml/scenario2-single-leaf-multiline-parent-expected.xml"
      actual_path = "spec/fixtures/xml/scenario2-single-leaf-multiline-parent-actual.xml"

      diff = format_diff(expected_path, actual_path)
      puts "\n" + "="*80
      puts "SCENARIO 2: Single leaf change in multi-line parent"
      puts "="*80
      puts diff
      puts "="*80

      # The diff should show:
      # - Opening <text> tag (line 5)
      # - Lines 6-8 (the context with <bold>highlighted</bold>)
      # - Closing </text> tag (line 11)
      # + Compressed single line with <em>highlighted</em>
      #
      # It should NOT show lines before the opening <text> or after closing </text>
    end
  end

  describe "Scenario 3: Multiple leaf changes in same parent" do
    it "shows parent element containing all changes" do
      expected_path = "spec/fixtures/xml/scenario3-multiple-leaves-same-parent-expected.xml"
      actual_path = "spec/fixtures/xml/scenario3-multiple-leaves-same-parent-actual.xml"

      diff = format_diff(expected_path, actual_path)
      puts "\n" + "="*80
      puts "SCENARIO 3: Multiple leaf changes in same parent"
      puts "="*80
      puts diff
      puts "="*80

      # The diff should show:
      # - Opening <text> tag
      # - All lines 6-8 with <bold>, <italic>, <underline>
      # - Closing </text> tag
      # + Single compressed line with <em>, <strong>, <code>
    end
  end

  describe "Scenario 4: Nested parents with changes" do
    it "shows only the immediate parent containing changes, not all ancestors" do
      expected_path = "spec/fixtures/xml/scenario4-nested-parents-expected.xml"
      actual_path = "spec/fixtures/xml/scenario4-nested-parents-actual.xml"

      diff = format_diff(expected_path, actual_path)
      puts "\n" + "="*80
      puts "SCENARIO 4: Nested parents with changes"
      puts "="*80
      puts diff
      puts "="*80

      # The diff should show:
      # - Opening <text> tag
      # - Lines with the <bold>nested</bold> change
      # - Closing </text> tag
      # + Compressed version
      #
      # It should NOT show:
      # - <outer>, <middle>, <inner> tags
      # - <unrelated> section
    end
  end

  describe "Scenario 5: Original isodoc blockquotes case" do
    it "shows complete attribution element with all missing lines" do
      expected_path = "spec/fixtures/xml/isodoc-blockquotes-expected.xml"
      actual_path = "spec/fixtures/xml/isodoc-blockquotes-actual.xml"

      diff = format_diff(expected_path, actual_path)
      puts "\n" + "="*80
      puts "SCENARIO 5: Original isodoc blockquotes case"
      puts "="*80
      puts diff
      puts "="*80

      # The diff should show ALL lines from the <p> element inside <attribution>
      # Currently it's missing lines after line 21 in the diff output
    end
  end
end
