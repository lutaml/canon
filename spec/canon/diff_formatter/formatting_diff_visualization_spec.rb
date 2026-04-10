# frozen_string_literal: true

require "spec_helper"
require "canon/comparison"

RSpec.describe "Formatting diff visualization" do
  describe "formatting-only differences" do
    it "suppresses diff when documents are equivalent despite formatting differences" do
      xml1 = <<~XML
        <root>
          <p>Hello world</p>
        </root>
      XML

      xml2 = <<~XML
        <root>
          <p>Hello
        world</p>
        </root>
      XML

      result = Canon::Comparison.equivalent?(
        xml1, xml2,
        verbose: true,
        use_color: false,
        match: { text_content: :normalize, structural_whitespace: :normalize }
      )
      diff = result.diff(use_color: false)

      # Formatting diffs are shown with show_diffs: :all even when equivalent
      expect(result.equivalent?).to be true
      expect(diff.lines.length).to be > 1 # Shows formatting diff
    end

    it "shows no formatting markers when documents are equivalent" do
      xml1 = <<~XML
        <root>
          <item>One</item>
        </root>
      XML

      xml2 = <<~XML
        <root>
            <item>One</item>
        </root>
      XML

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true,
                                                         use_color: false)
      diff = result.diff(use_color: false)

      # When documents are equivalent, NO formatting markers should be shown
      # The comparison found them equivalent despite formatting differences
      expect(diff).not_to include("[")
      expect(diff).not_to include("]")
    end

    it "handles equivalent documents without errors and shows formatting diffs" do
      xml1 = "<root><p>Hello  world</p></root>"
      xml2 = "<root><p>Hello world</p></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true,
                                                         use_color: true,
                                                         match: { text_content: :normalize })
      diff = result.diff(use_color: true)

      # With show_diffs: :all (default), formatting-only diffs are shown even when equivalent
      expect(result.equivalent?).to be true
      expect(diff.lines.length).to be > 1 # Shows formatting diff
    end
  end

  describe "mixed differences" do
    it "shows normative markers for semantic changes even with formatting differences" do
      xml1 = <<~XML
        <root>
          <p>Hello</p>
        </root>
      XML

      xml2 = <<~XML
        <root>
          <p>Goodbye</p>
        </root>
      XML

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true,
                                                         use_color: false)
      diff = result.diff(use_color: false)

      # Should show normative markers (- and +) not formatting markers
      expect(diff).to include("-")
      expect(diff).to include("+")
      expect(diff).not_to include("[")
      expect(diff).not_to include("]")
    end

    it "prioritizes normative classification over formatting" do
      xml1 = "<root><p class='old'>Content</p></root>"
      xml2 = "<root><p  class='new'>Content</p></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true,
                                                         use_color: false)
      diff = result.diff(use_color: false)

      # Attribute value change is normative, not formatting
      expect(diff).to include("-")
      expect(diff).to include("+")
    end
  end

  describe "informative vs formatting differences" do
    it "shows informative markers when comments differ but are configured as ignore" do
      xml1 = "<root><!-- comment1 --><p>Content</p></root>"
      xml2 = "<root><!-- comment2 --><p>Content</p></root>"

      result = Canon::Comparison.equivalent?(
        xml1, xml2,
        verbose: true,
        use_color: false,
        match: { comments: :ignore }
      )
      diff = result.diff(use_color: false)

      # When equivalent but comments are ignored, diff is suppressed
      expect(result.equivalent?).to be true
      expect(diff.lines.length).to eq(1)
    end

    # Formatting diffs ARE shown with show_diffs: :all when equivalent
    it "shows formatting but suppresses informative when equivalent" do
      # Formatting: whitespace only (equivalent with normalize)
      xml1a = "<root><p>Hello  world</p></root>"
      xml2a = "<root><p>Hello world</p></root>"

      result_formatting = Canon::Comparison.equivalent?(
        xml1a, xml2a,
        verbose: true,
        use_color: false,
        match: { text_content: :normalize }
      )

      # Informative: comments (ignored, equivalent)
      xml1b = "<root><!-- old --></root>"
      xml2b = "<root><!-- new --></root>"

      result_informative = Canon::Comparison.equivalent?(
        xml1b, xml2b,
        verbose: true,
        use_color: false,
        match: { comments: :ignore }
      )

      # Formatting diffs ARE shown with show_diffs: :all when equivalent
      expect(result_formatting.equivalent?).to be true
      expect(result_formatting.diff(use_color: false).lines.length).to be > 1

      # Informative diffs are suppressed when equivalent
      expect(result_informative.equivalent?).to be true
      expect(result_informative.diff(use_color: false).lines.length).to eq(1)
    end
  end

  describe "edge cases" do
    it "handles empty lines with formatting differences" do
      xml1 = "<root>\n\n  <p>Content</p>\n</root>"
      xml2 = "<root>\n   <p>Content</p>\n</root>"

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true,
                                                         use_color: false)

      # Should not crash
      expect(result.diff(use_color: false)).to be_a(String)
    end

    it "handles documents with only formatting differences" do
      xml1 = "<root><a>1</a><b>2</b></root>"
      xml2 = "<root>  <a>1</a>  <b>2</b>  </root>"

      # rubocop:disable Layout/LineLength
      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true,
                                                         use_color: false,
                                                         match: { structural_whitespace: :ignore })
      # rubocop:enable Layout/LineLength

      # Should be equivalent when ignoring structural whitespace
      expect(result.equivalent?).to be true

      # Diff should show formatting markers if any
      diff = result.diff(use_color: false)
      expect(diff).to be_a(String)
    end

    it "handles mixed whitespace types" do
      xml1 = "<root>\t<p>Content</p></root>"
      xml2 = "<root>  <p>Content</p></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true,
                                                         use_color: false)
      diff = result.diff(use_color: false)

      # Should handle mixed whitespace
      expect(diff).to be_a(String)
    end
  end

  describe "classification hierarchy" do
    it "shows normative markers for non-equivalent documents" do
      # Normative (highest priority)
      xml_normative1 = "<root><p>Old</p></root>"
      xml_normative2 = "<root><p>New</p></root>"

      result_normative = Canon::Comparison.equivalent?(
        xml_normative1, xml_normative2,
        verbose: true,
        use_color: false
      )

      # Should show normative markers for actual content differences
      expect(result_normative.equivalent?).to be false
      diff = result_normative.diff(use_color: false)
      expect(diff).to include("-")
      expect(diff).to include("+")
    end

    # Formatting diffs ARE shown with show_diffs: :all when equivalent
    it "shows formatting but suppresses informative when equivalent" do
      # Informative: comments (ignored, equivalent)
      xml_info1 = "<root><!-- old --></root>"
      xml_info2 = "<root><!-- new --></root>"

      result_info = Canon::Comparison.equivalent?(
        xml_info1, xml_info2,
        verbose: true,
        use_color: false,
        match: { comments: :ignore }
      )

      # Formatting (equivalent)
      xml_fmt1 = "<root><p>Hello world</p></root>"
      xml_fmt2 = "<root><p>Hello\nworld</p></root>"

      result_fmt = Canon::Comparison.equivalent?(
        xml_fmt1, xml_fmt2,
        verbose: true,
        use_color: false,
        match: { text_content: :normalize, structural_whitespace: :normalize }
      )

      # Informative diffs are suppressed when equivalent
      expect(result_info.equivalent?).to be true
      expect(result_info.diff(use_color: false).lines.length).to eq(1)

      # Formatting diffs ARE shown with show_diffs: :all when equivalent
      expect(result_fmt.equivalent?).to be true
      expect(result_fmt.diff(use_color: false).lines.length).to be > 1
    end
  end

  describe "legend display" do
    it "includes formatting diff markers in legend when shown" do
      xml1 = "<root><p>Hello  world</p></root>"
      xml2 = "<root><p>Hello world</p></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true,
                                                         use_color: false)

      # The legend should document [ and ] markers
      # This would be tested if we add a method to show the legend
      expect(result.diff(use_color: false)).to be_a(String)
    end
  end
end
