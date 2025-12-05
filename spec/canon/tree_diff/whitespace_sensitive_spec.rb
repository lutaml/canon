# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Whitespace-sensitive elements" do
  describe "HTML <pre> elements" do
    it "treats whitespace changes in <pre> as NORMATIVE" do
      expected = <<~HTML
        <pre>

        </pre>
      HTML

      actual = <<~HTML
        <pre>    </pre>
      HTML

      result = Canon::Comparison.equivalent?(
        expected,
        actual,
        format: :html,
        diff_algorithm: :semantic_tree,
        verbose: true,
      )

      expect(result.equivalent?).to be false

      # The diff should be marked as normative (not informative)
      # because whitespace in <pre> elements affects rendering
      normative_diffs = result.differences.select(&:normative?)
      expect(normative_diffs).not_to be_empty
    end

    it "treats identical <pre> content as equivalent" do
      html1 = <<~HTML
        <pre>Multiple    spaces   and
        newlines    should
        be preserved</pre>
      HTML

      html2 = <<~HTML
        <pre>Multiple    spaces   and
        newlines    should
        be preserved</pre>
      HTML

      expect(html1).to be_html_equivalent_to(html2,
                                             diff_algorithm: :semantic_tree)
    end

    it "treats different whitespace in <pre> as non-equivalent" do
      html1 = <<~HTML
        <pre>Multiple    spaces   and
        newlines    should
        be preserved</pre>
      HTML

      html2 = "<pre>Multiple spaces and newlines should be preserved</pre>"

      expect(html1).not_to be_html_equivalent_to(html2,
                                                 diff_algorithm: :semantic_tree)
    end
  end

  describe "HTML <code> elements" do
    it "treats whitespace changes in <code> as NORMATIVE" do
      html1 = "<code>const x    =    5;</code>"
      html2 = "<code>const x = 5;</code>"

      result = Canon::Comparison.equivalent?(
        html1,
        html2,
        format: :html,
        diff_algorithm: :semantic_tree,
        verbose: true,
      )

      expect(result.equivalent?).to be false

      # Should be marked as normative
      normative_diffs = result.differences.select(&:normative?)
      expect(normative_diffs).not_to be_empty
    end
  end

  describe "HTML <textarea> elements" do
    it "treats whitespace changes in <textarea> as NORMATIVE" do
      html1 = "<textarea>  leading spaces</textarea>"
      html2 = "<textarea>leading spaces</textarea>"

      result = Canon::Comparison.equivalent?(
        html1,
        html2,
        format: :html,
        diff_algorithm: :semantic_tree,
        verbose: true,
      )

      expect(result.equivalent?).to be false
      normative_diffs = result.differences.select(&:normative?)
      expect(normative_diffs).not_to be_empty
    end
  end

  describe "Regular HTML elements (non-whitespace-sensitive)" do
    it "treats whitespace changes in <p> as informative with normalize mode" do
      html1 = <<~HTML
        <p>Multiple    spaces   and
        newlines    should
        collapse</p>
      HTML

      html2 = "<p>Multiple spaces and newlines should collapse</p>"

      # With normalize (default), these should be equivalent
      expect(html1).to be_html_equivalent_to(html2,
                                             match: { text_content: :normalize })
    end
  end
end
