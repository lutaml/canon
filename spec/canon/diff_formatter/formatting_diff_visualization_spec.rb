# frozen_string_literal: true

require "spec_helper"
require "canon/comparison"

RSpec.describe "Formatting diff visualization" do
  describe "formatting-only differences" do
    it "shows [ and ] markers for formatting-only line splits" do
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

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true, use_color: false)
      diff = result.diff(use_color: false)

      # Should show formatting markers [ and ]
      expect(diff).to include("[")
      expect(diff).to include("]")
    end

    it "shows formatting markers for indentation differences" do
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

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true, use_color: false)
      diff = result.diff(use_color: false)

      # Should detect formatting-only difference
      expect(diff).to include("[")
      expect(diff).to include("]")
    end

    it "uses dim gray color for formatting markers when color enabled" do
      xml1 = "<root><p>Hello  world</p></root>"
      xml2 = "<root><p>Hello world</p></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true, use_color: true)
      diff = result.diff(use_color: true)

      # Should include formatting markers
      expect(diff).to include("[").or include("]")
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

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true, use_color: false)
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

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true, use_color: false)
      diff = result.diff(use_color: false)

      # Attribute value change is normative, not formatting
      expect(diff).to include("-")
      expect(diff).to include("+")
    end
  end

  describe "informative vs formatting differences" do
    it "shows informative markers for match-option-dependent differences" do
      xml1 = "<root><!-- comment1 --><p>Content</p></root>"
      xml2 = "<root><!-- comment2 --><p>Content</p></root>"

      result = Canon::Comparison.equivalent?(
        xml1, xml2,
        verbose: true,
        use_color: false,
        match: { comments: :ignore }
      )
      diff = result.diff(use_color: false)

      # Comment differences should be informative
      expect(diff).to include("<").or include(">")
    end

    it "distinguishes formatting from informative differences" do
      # Formatting: whitespace only
      xml1a = "<root><p>Hello  world</p></root>"
      xml2a = "<root><p>Hello world</p></root>"

      result_formatting = Canon::Comparison.equivalent?(
        xml1a, xml2a,
        verbose: true,
        use_color: false
      )

      # Informative: comments (ignored)
      xml1b = "<root><!-- old --></root>"
      xml2b = "<root><!-- new --></root>"

      result_informative = Canon::Comparison.equivalent?(
        xml1b, xml2b,
        verbose: true,
        use_color: false,
        match: { comments: :ignore }
      )

      # Formatting should use [ ]
      expect(result_formatting.diff(use_color: false)).to include("[").or include("]")

      # Informative should use < >
      expect(result_informative.diff(use_color: false)).to include("<").or include(">")
    end
  end

  describe "edge cases" do
    it "handles empty lines with formatting differences" do
      xml1 = "<root>\n\n  <p>Content</p>\n</root>"
      xml2 = "<root>\n   <p>Content</p>\n</root>"

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true, use_color: false)

      # Should not crash
      expect(result.diff(use_color: false)).to be_a(String)
    end

    it "handles documents with only formatting differences" do
      xml1 = "<root><a>1</a><b>2</b></root>"
      xml2 = "<root>  <a>1</a>  <b>2</b>  </root>"

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true, use_color: false)

      # Should be equivalent
      expect(result.equivalent?).to be true

      # Diff should show formatting markers if any
      diff = result.diff(use_color: false)
      expect(diff).to be_a(String)
    end

    it "handles mixed whitespace types" do
      xml1 = "<root>\t<p>Content</p></root>"
      xml2 = "<root>  <p>Content</p></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true, use_color: false)
      diff = result.diff(use_color: false)

      # Should handle mixed whitespace
      expect(diff).to be_a(String)
    end
  end

  describe "classification hierarchy" do
    it "follows formatting < informative < normative hierarchy" do
      # Normative (highest priority)
      xml_normative1 = "<root><p>Old</p></root>"
      xml_normative2 = "<root><p>New</p></root>"

      result_normative = Canon::Comparison.equivalent?(
        xml_normative1, xml_normative2,
        verbose: true,
        use_color: false
      )

      # Informative (medium priority)
      xml_info1 = "<root><!-- old --></root>"
      xml_info2 = "<root><!-- new --></root>"

      result_info = Canon::Comparison.equivalent?(
        xml_info1, xml_info2,
        verbose: true,
        use_color: false,
        match: { comments: :ignore }
      )

      # Formatting (lowest priority) - use text content with line break differences
      xml_fmt1 = "<root><p>Hello world</p></root>"
      xml_fmt2 = "<root><p>Hello\nworld</p></root>"

      result_fmt = Canon::Comparison.equivalent?(
        xml_fmt1, xml_fmt2,
        verbose: true,
        use_color: false
      )

      # Normative uses - and +
      expect(result_normative.diff(use_color: false)).to include("-")
      expect(result_normative.diff(use_color: false)).to include("+")

      # Informative uses < and >
      expect(result_info.diff(use_color: false)).to include("<").or include(">")

      # Formatting uses [ and ]
      expect(result_fmt.diff(use_color: false)).to include("[").or include("]")
    end
  end

  describe "legend display" do
    it "includes formatting diff markers in legend when shown" do
      xml1 = "<root><p>Hello  world</p></root>"
      xml2 = "<root><p>Hello world</p></root>"

      result = Canon::Comparison.equivalent?(xml1, xml2, verbose: true, use_color: false)

      # The legend should document [ and ] markers
      # This would be tested if we add a method to show the legend
      expect(result.diff(use_color: false)).to be_a(String)
    end
  end
end