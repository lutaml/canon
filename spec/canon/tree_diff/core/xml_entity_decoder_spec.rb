# frozen_string_literal: true

RSpec.describe Canon::TreeDiff::Core::XmlEntityDecoder do
  describe ".decode_xml_entities" do
    it "decodes hex entity for left double quotation mark" do
      result = described_class.decode_xml_entities("&#x201C;")
      expect(result.bytes).to eq([226, 128, 156]) # U+201C
    end

    it "decodes hex entity for right double quotation mark" do
      result = described_class.decode_xml_entities("&#x201D;")
      expect(result.bytes).to eq([226, 128, 157]) # U+201D
    end

    it "decodes named entity &amp;" do
      result = described_class.decode_xml_entities("&amp;")
      expect(result).to eq("&")
    end

    it "decodes named entity &lt;" do
      result = described_class.decode_xml_entities("&lt;")
      expect(result).to eq("<")
    end

    it "decodes named entity &gt;" do
      result = described_class.decode_xml_entities("&gt;")
      expect(result).to eq(">")
    end

    it "decodes named entity &quot;" do
      result = described_class.decode_xml_entities("&quot;")
      expect(result).to eq('"')
    end

    it "decodes named entity &apos;" do
      result = described_class.decode_xml_entities("&apos;")
      expect(result).to eq("'")
    end

    it "decodes decimal numeric entity" do
      # &#169; = U+00A9 (copyright symbol)
      result = described_class.decode_xml_entities("&#169;")
      expect(result.bytes).to eq([194, 169])
    end

    it "decodes hexadecimal numeric entity with uppercase X" do
      result = described_class.decode_xml_entities("&#X201C;")
      expect(result.bytes).to eq([226, 128, 156])
    end

    it "preserves unknown entities" do
      result = described_class.decode_xml_entities("&unknown;")
      expect(result).to eq("&unknown;")
    end

    it "returns original text when no entities present" do
      text = "hello world"
      result = described_class.decode_xml_entities(text)
      expect(result).to eq(text)
    end

    it "handles mixed entity and regular text" do
      result = described_class.decode_xml_entities("Hello &#x201C;world&#x201D;")
      expected = "Hello #{0x201C.chr(Encoding::UTF_8)}world#{0x201D.chr(Encoding::UTF_8)}"
      expect(result).to eq(expected)
    end

    it "handles empty string" do
      expect(described_class.decode_xml_entities("")).to eq("")
    end

    it "handles nil" do
      expect(described_class.decode_xml_entities(nil)).to be_nil
    end
  end

  describe ".decode_entity" do
    it "decodes &amp; to &" do
      expect(described_class.decode_entity("&amp;")).to eq("&")
    end

    it "decodes decimal entity &#169; to copyright symbol" do
      result = described_class.decode_entity("&#169;")
      expect(result.bytes).to eq([194, 169])
    end

    it "decodes hex entity &#x00A9; to copyright symbol" do
      result = described_class.decode_entity("&#x00A9;")
      expect(result.bytes).to eq([194, 169])
    end

    it "returns unknown entities unchanged" do
      expect(described_class.decode_entity("&bogus;")).to eq("&bogus;")
    end
  end

  describe ".decode_codepoint" do
    it "decodes valid code point" do
      expect(described_class.decode_codepoint(65)).to eq("A")
    end

    it "returns empty string for zero" do
      expect(described_class.decode_codepoint(0)).to eq("")
    end

    it "returns empty string for code point above max" do
      expect(described_class.decode_codepoint(0x110000)).to eq("")
    end
  end
end
