# frozen_string_literal: true

require "spec_helper"
require "canon/diff_formatter"

RSpec.describe "Normative diffs visible in by_line mode" do
  describe "identical siblings (issue #85 mechanism)" do
    # The deleted second <biblio-tag> is byte-identical to the first.
    # The enricher must anchor element deletions by the path's element
    # index, not the first substring match, or the deletion collides
    # with the first sibling's change and the line builder absorbs it
    # into a formatting-only summary.
    let(:xml_expected) do
      <<~XML
        <bibitem id="ISO712">
          <biblio-tag>ISO 712, </biblio-tag>
          <title format="text/plain">Cereals and cereal products</title>
          <biblio-tag>ISO 712, </biblio-tag>
        </bibitem>
      XML
    end
    let(:xml_actual) do
      %(<bibitem id="ISO712"><biblio-tag>ISO\u00A0712, </biblio-tag><title format="text/plain">Cereals and cereal products</title></bibitem>)
    end

    it "anchors an identical-sibling deletion at the right element" do
      result = Canon::Comparison.equivalent?(xml_expected, xml_actual,
                                             format: :xml, verbose: true)
      # Line ranges are assigned by the formatter pipeline's enricher.
      Canon::Diff::DiffNodeEnricher.build(result.differences, xml_expected,
                                          xml_actual)
      deletion = result.differences.find do |d|
        d.dimension == :element_structure && d.line_range_before
      end
      expect(deletion).not_to be_nil
      # The deleted biblio-tag is the SECOND one (line 3 in this
      # fixture), not the first (line 1).
      expect(deletion.line_range_before[0]).to eq(3)
    end

    it "renders the identical-sibling deletion instead of absorbing it" do
      result = Canon::Comparison.equivalent?(xml_expected, xml_actual,
                                             format: :xml, verbose: true)
      formatter = Canon::DiffFormatter.new(
        use_color: false,
        mode: :by_line,
        display_preprocessing: :pretty_print,
        show_diffs: :normative,
      )
      output = formatter.format(result.differences, :xml,
                                doc1: xml_expected, doc2: xml_actual)
      # A removed line for the second biblio-tag must be present —
      # count the removed markers: the NBSP change contributes one
      # removed line, the deletion contributes another.
      removed_lines = output.scan(/^\s*\|?\s*\d+\s*\|\s*-\s*\|/m)
      expect(removed_lines.length).to eq(2)
    end
  end

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
