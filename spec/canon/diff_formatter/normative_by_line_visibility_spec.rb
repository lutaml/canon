# frozen_string_literal: true

require "spec_helper"
require "canon/diff_formatter"

RSpec.describe "Normative diffs visible in by_line mode" do
  describe "different serialization formats with normative text change" do
    let(:xml_compact) { "<p>Hello <em>World</em> text</p>" }
    let(:xml_expanded) { "<p>\n  Hello\n  <em>Changed</em>\n  text\n</p>" }

    it "shows normative diffs with show_diffs: :normative" do
      result = Canon::Comparison.equivalent?(xml_compact, xml_expanded,
                                             verbose: true)
      expect(result.equivalent?).to be false

      # Verify the normative DiffNode exists
      normative = result.differences.select(&:normative?)
      expect(normative).not_to be_empty

      formatter = Canon::DiffFormatter.new(
        use_color: false,
        mode: :by_line,
        show_diffs: :normative,
      )
      output = formatter.format(result, :xml, doc1: xml_compact,
                                               doc2: xml_expanded)

      # The output MUST contain the normative change markers
      expect(output).to include("-")
      expect(output).to include("+")
      # The removed line should contain "World"
      expect(output).to include("World")
    end

    it "shows diffs with show_diffs: :all (regression guard)" do
      result = Canon::Comparison.equivalent?(xml_compact, xml_expanded,
                                             verbose: true)
      formatter = Canon::DiffFormatter.new(
        use_color: false,
        mode: :by_line,
        show_diffs: :all,
      )
      output = formatter.format(result, :xml, doc1: xml_compact,
                                               doc2: xml_expanded)

      expect(output).to include("-")
      expect(output).to include("+")
      expect(output).to include("World")
    end
  end

  describe "equivalent documents with different formatting" do
    let(:xml_compact) { "<root><a><b>text</b></a></root>" }
    let(:xml_expanded) { "<root>\n  <a>\n    <b>text</b>\n  </a>\n</root>" }

    it "shows no normative diffs with show_diffs: :normative" do
      result = Canon::Comparison.equivalent?(xml_compact, xml_expanded,
                                             verbose: true)
      # These should be equivalent (same content, different formatting)
      expect(result.equivalent?).to be true

      formatter = Canon::DiffFormatter.new(
        use_color: false,
        mode: :by_line,
        show_diffs: :normative,
      )
      output = formatter.format(result, :xml, doc1: xml_compact,
                                               doc2: xml_expanded)

      # No normative diffs should appear
      expect(output).not_to include("World")
      expect(output).not_to include("Changed")
    end
  end
end
