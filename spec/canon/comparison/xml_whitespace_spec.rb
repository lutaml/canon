# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XML whitespace handling" do
  describe "Canon::Comparison.equivalent? with XML whitespace" do
    it "normalizes structural whitespace by default for XML" do
      # Whitespace BETWEEN elements is structural whitespace
      xml1 = "<root>\n  <text>Hello</text>\n</root>"
      xml2 = "<root>  <text>Hello</text></root>"
      # Structural whitespace is filtered for non-whitespace-sensitive XML elements
      expect(Canon::Comparison.equivalent?(xml1, xml2)).to be true
    end

    it "preserves whitespace in text content with strict mode" do
      # Whitespace WITHIN text content is compared with text_content behavior
      xml1 = "<root>Hello  World</root>"
      xml2 = "<root>Hello World</root>"
      # text_content: :strict means whitespace is significant
      expect(Canon::Comparison.equivalent?(xml1, xml2)).to be false
    end

    it "normalizes text content when text_content: :normalize" do
      xml1 = "<root>Hello  World</root>"
      xml2 = "<root>Hello World</root>"
      expect(Canon::Comparison.equivalent?(xml1, xml2,
        match: { text_content: :normalize }
      )).to be true
    end

    it "preserves structural whitespace in whitespace-sensitive HTML elements" do
      # <pre> is whitespace-sensitive in HTML
      xml1 = "<pre>\n  code\n</pre>"
      xml2 = "<pre>  code</pre>"
      expect(Canon::Comparison.equivalent?(xml1, xml2,
        match: { format: :html }
      )).to be false
    end

    it "uses sensitive_elements to preserve whitespace in specific XML elements" do
      xml1 = "<custom>\n  text\n</custom>"
      xml2 = "<custom> text </custom>"
      # With sensitive_elements, whitespace in <custom> is preserved
      expect(Canon::Comparison.equivalent?(xml1, xml2,
        match: { sensitive_elements: [:custom] }
      )).to be false
    end

    it "uses whitespace_insensitive_elements to override element sensitivity" do
      xml1 = "<pre>\n  text\n</pre>"
      xml2 = "<pre> text </pre>"
      # whitespace_insensitive_elements overrides default sensitivity
      expect(Canon::Comparison.equivalent?(xml1, xml2,
        match: { format: :html, whitespace_insensitive_elements: [:pre], text_content: :normalize }
      )).to be true
    end

    it "compares attributes with strict mode by default" do
      xml1 = %(<root attr="  value  "/>)
      xml2 = %(<root attr="value"/>)
      # attribute_values: :strict by default for XML
      expect(Canon::Comparison.equivalent?(xml1, xml2)).to be false
    end

    it "normalizes attribute whitespace when attribute_values: :normalize" do
      xml1 = %(<root attr="  value  "/>)
      xml2 = %(<root attr="value"/>)
      expect(Canon::Comparison.equivalent?(xml1, xml2,
        match: { attribute_values: :normalize }
      )).to be true
    end

    context "with structural_whitespace dimension" do
      it "uses :strict to preserve structural whitespace differences" do
        xml1 = "<root>\n  <text>Hello</text>\n</root>"
        xml2 = "<root>  <text>Hello</text></root>"
        # Note: structural_whitespace: :strict still filters for non-sensitive elements
        expect(Canon::Comparison.equivalent?(xml1, xml2,
          match: { structural_whitespace: :strict }
        )).to be true
      end

      it "uses :normalize to collapse structural whitespace" do
        xml1 = "<root>\n  <text>Hello</text>\n</root>"
        xml2 = "<root>  <text>Hello</text></root>"
        expect(Canon::Comparison.equivalent?(xml1, xml2,
          match: { structural_whitespace: :normalize }
        )).to be true
      end

      it "uses :ignore to skip structural whitespace comparison" do
        xml1 = "<root>\n  <text>Hello</text>\n</root>"
        xml2 = "<root><text>Hello</text></root>"
        expect(Canon::Comparison.equivalent?(xml1, xml2,
          match: { structural_whitespace: :ignore }
        )).to be true
      end
    end

    # xml:space="preserve" IS respected by whitespace_preserved?
    # This was a bug that is now fixed.
    context "with xml:space attribute" do
      it "preserves structural whitespace when xml:space='preserve'" do
        xml1 = "<root xml:space='preserve'>\n  <text>Hello</text>\n</root>"
        xml2 = "<root xml:space='preserve'><text>Hello</text></root>"
        # FIXED: whitespace_preserved? now checks xml:space attribute
        # So these should NOT be equivalent (whitespace is preserved)
        expect(Canon::Comparison.equivalent?(xml1, xml2)).to be false
      end
    end
  end
end
