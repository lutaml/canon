# frozen_string_literal: true

require "spec_helper"
require "canon/diff/xml_serialization_formatter"
require "canon/diff/diff_node"

RSpec.describe Canon::Diff::XmlSerializationFormatter do
  describe ".serialization_formatting?" do
    context "with self-closing vs explicit closing tags" do
      it "detects empty text nodes from self-closing vs explicit closing" do
        # Create mock text nodes
        node1 = double("TextNode", value: "")
        node2 = double("TextNode", value: "   ")

        diff_node = Canon::Diff::DiffNode.new(
          node1: node1,
          node2: node2,
          dimension: :text_content,
          reason: "UNEQUAL_TEXT_CONTENTS"
        )

        expect(described_class.serialization_formatting?(diff_node)).to be true
      end

      it "detects whitespace-only text nodes from self-closing vs explicit closing" do
        node1 = double("TextNode", value: "\n")
        node2 = double("TextNode", value: "  \t  ")

        diff_node = Canon::Diff::DiffNode.new(
          node1: node1,
          node2: node2,
          dimension: :text_content,
          reason: "UNEQUAL_TEXT_CONTENTS"
        )

        expect(described_class.serialization_formatting?(diff_node)).to be true
      end

      it "returns false for non-text_content dimensions" do
        node1 = double("TextNode", value: "")
        node2 = double("TextNode", value: "")

        diff_node = Canon::Diff::DiffNode.new(
          node1: node1,
          node2: node2,
          dimension: :attribute_order,
          reason: "UNEQUAL_ATTRIBUTE_ORDER"
        )

        expect(described_class.serialization_formatting?(diff_node)).to be false
      end
    end

    context "with actual content differences" do
      it "returns false for text with actual content" do
        node1 = double("TextNode", value: "Hello")
        node2 = double("TextNode", value: "Goodbye")

        diff_node = Canon::Diff::DiffNode.new(
          node1: node1,
          node2: node2,
          dimension: :text_content,
          reason: "UNEQUAL_TEXT_CONTENTS"
        )

        expect(described_class.serialization_formatting?(diff_node)).to be false
      end

      it "returns false when one text is blank and one has content" do
        node1 = double("TextNode", value: "")
        node2 = double("TextNode", value: "Hello")

        diff_node = Canon::Diff::DiffNode.new(
          node1: node1,
          node2: node2,
          dimension: :text_content,
          reason: "UNEQUAL_TEXT_CONTENTS"
        )

        expect(described_class.serialization_formatting?(diff_node)).to be false
      end
    end

    context "with real XML parsing" do
      it "handles empty text nodes from explicit closing tags" do
        # When an element has whitespace inside, Nokogiri creates text nodes
        xml1 = "<root><item>   </item></root>"
        xml2 = "<root><item>\t</item></root>"

        doc1 = Nokogiri::XML(xml1)
        doc2 = Nokogiri::XML(xml2)

        text1 = doc1.xpath("/root/item/text()").first
        text2 = doc2.xpath("/root/item/text()").first

        # Both are whitespace-only text nodes
        expect(text1).not_to be_nil
        expect(text2).not_to be_nil

        diff_node = Canon::Diff::DiffNode.new(
          node1: text1,
          node2: text2,
          dimension: :text_content,
          reason: "UNEQUAL_TEXT_CONTENTS"
        )

        result = described_class.serialization_formatting?(diff_node)

        # Should detect as serialization formatting (both are blank/whitespace-only)
        expect(result).to be true
      end

      it "returns false for actual text content differences" do
        xml1 = "<root><item>text1</item></root>"
        xml2 = "<root><item>text2</item></root>"

        doc1 = Nokogiri::XML(xml1)
        doc2 = Nokogiri::XML(xml2)

        text1 = doc1.xpath("/root/item/text()").first
        text2 = doc2.xpath("/root/item/text()").first

        diff_node = Canon::Diff::DiffNode.new(
          node1: text1,
          node2: text2,
          dimension: :text_content,
          reason: "UNEQUAL_TEXT_CONTENTS"
        )

        expect(described_class.serialization_formatting?(diff_node)).to be false
      end

      it "returns false when both are nil (no text content)" do
        xml1 = "<root><item/></root>"
        xml2 = "<root><item></item></root>"

        doc1 = Nokogiri::XML(xml1)
        doc2 = Nokogiri::XML(xml2)

        text1 = doc1.xpath("/root/item/text()").first
        text2 = doc2.xpath("/root/item/text()").first

        diff_node = Canon::Diff::DiffNode.new(
          node1: text1,
          node2: text2,
          dimension: :text_content,
          reason: "UNEQUAL_TEXT_CONTENTS"
        )

        # Both are nil - no actual difference
        expect(described_class.serialization_formatting?(diff_node)).to be false
      end
    end
  end

  describe ".blank?" do
    it "returns true for nil" do
      expect(described_class.send(:blank?, nil)).to be true
    end

    it "returns true for empty string" do
      expect(described_class.send(:blank?, "")).to be true
    end

    it "returns true for whitespace-only string" do
      expect(described_class.send(:blank?, "   ")).to be true
      expect(described_class.send(:blank?, "\t\n")).to be true
      expect(described_class.send(:blank?, "  \n\t  ")).to be true
    end

    it "returns false for non-blank string" do
      expect(described_class.send(:blank?, "text")).to be false
      expect(described_class.send(:blank?, " text ")).to be false
      expect(described_class.send(:blank?, "  text  ")).to be false
    end
  end

  describe ".text_node?" do
    context "with Canon::Xml::Nodes::TextNode" do
      it "returns true for Canon text nodes" do
        node = Canon::Xml::Nodes::TextNode.new(value: "text")
        expect(described_class.send(:text_node?, node)).to be true
      end
    end

    context "with Nokogiri nodes" do
      it "returns true for Nokogiri text nodes" do
        xml = "<root>text</root>"
        doc = Nokogiri::XML(xml)
        # Get text node via XPath
        text_node = doc.xpath("//text()").first

        expect(described_class.send(:text_node?, text_node)).to be true
      end

      it "returns false for Nokogiri element nodes" do
        xml = "<root><elem/></root>"
        doc = Nokogiri::XML(xml)
        elem_node = doc.xpath("//elem").first

        expect(described_class.send(:text_node?, elem_node)).to be false
      end
    end

    context "with Moxml nodes" do
      it "returns true for Moxml text nodes" do
        xml = "<root>text</root>"
        doc = Moxml.new.parse(xml)
        text_node = doc.xpath("/root/text()").first

        expect(described_class.send(:text_node?, text_node)).to be true
      end

      it "returns false for Moxml element nodes" do
        xml = "<root><elem/></root>"
        doc = Moxml.new.parse(xml)
        elem_node = doc.xpath("/root/elem").first

        expect(described_class.send(:text_node?, elem_node)).to be false
      end
    end

    context "with strings" do
      it "returns true for strings" do
        expect(described_class.send(:text_node?, "text")).to be true
      end
    end

    context "with objects with value method" do
      it "returns true for objects with value method" do
        obj = double("TextNode", value: "text")
        expect(described_class.send(:text_node?, obj)).to be true
      end
    end

    context "with nil" do
      it "returns false for nil" do
        expect(described_class.send(:text_node?, nil)).to be false
      end
    end
  end

  describe ".extract_text_content" do
    context "with Canon::Xml::Nodes::TextNode" do
      it "extracts value from Canon text nodes" do
        node = Canon::Xml::Nodes::TextNode.new(value: "sample text")
        expect(described_class.send(:extract_text_content, node)).to eq("sample text")
      end
    end

    context "with Nokogiri nodes" do
      it "extracts text_content from Nokogiri text nodes" do
        xml = "<root>sample text</root>"
        doc = Nokogiri::XML(xml)
        text_node = doc.xpath("//text()").first

        expect(described_class.send(:extract_text_content, text_node)).to eq("sample text")
      end

      it "extracts content from Nokogiri nodes" do
        xml = "<root>sample text</root>"
        doc = Nokogiri::XML(xml)
        elem_node = doc.xpath("/root").first

        expect(described_class.send(:extract_text_content, elem_node)).to eq("sample text")
      end
    end

    context "with Moxml nodes" do
      it "extracts text from Moxml text nodes" do
        xml = "<root>sample text</root>"
        doc = Moxml.new.parse(xml)
        text_node = doc.xpath("/root/text()").first

        expect(described_class.send(:extract_text_content, text_node)).to eq("sample text")
      end
    end

    context "with strings" do
      it "returns the string itself" do
        expect(described_class.send(:extract_text_content, "text")).to eq("text")
      end
    end

    context "with nil" do
      it "returns nil" do
        expect(described_class.send(:extract_text_content, nil)).to be_nil
      end
    end

    context "with objects with various content methods" do
      it "tries text_content method first" do
        obj = double("Node", text_content: "via text_content", text: "via text")
        expect(described_class.send(:extract_text_content, obj)).to eq("via text_content")
      end

      it "falls back to text method" do
        obj = double("Node", text: "via text")
        expect(described_class.send(:extract_text_content, obj)).to eq("via text")
      end

      it "falls back to content method" do
        obj = double("Node", content: "via content")
        expect(described_class.send(:extract_text_content, obj)).to eq("via content")
      end

      it "falls back to value method" do
        obj = double("Node", value: "via value")
        expect(described_class.send(:extract_text_content, obj)).to eq("via value")
      end

      it "falls back to to_s" do
        obj = double("Node", to_s: "via to_s")
        expect(described_class.send(:extract_text_content, obj)).to eq("via to_s")
      end
    end

    context "with error handling" do
      it "returns nil when extraction raises an error" do
        obj = double("Node")
        allow(obj).to receive(:text_content).and_raise(StandardError, "error")
        expect(described_class.send(:extract_text_content, obj)).to be_nil
      end
    end
  end

  describe ".empty_text_content_serialization_diff?" do
    it "returns false for non-text_content dimensions" do
      node1 = double("TextNode", value: "")
      node2 = double("TextNode", value: "")

      diff_node = Canon::Diff::DiffNode.new(
        node1: node1,
        node2: node2,
        dimension: :attribute_order,
        reason: "UNEQUAL_ATTRIBUTE_ORDER"
      )

      expect(described_class.send(:empty_text_content_serialization_diff?, diff_node)).to be false
    end

    it "returns false when nodes are not text nodes" do
      node1 = double("ElementNode", name: "div")
      node2 = double("ElementNode", name: "div")

      diff_node = Canon::Diff::DiffNode.new(
        node1: node1,
        node2: node2,
        dimension: :text_content,
        reason: "UNEQUAL_TEXT_CONTENTS"
      )

      expect(described_class.send(:empty_text_content_serialization_diff?, diff_node)).to be false
    end

    it "returns true when both texts are blank" do
      node1 = double("TextNode", value: "")
      node2 = double("TextNode", value: "   ")

      diff_node = Canon::Diff::DiffNode.new(
        node1: node1,
        node2: node2,
        dimension: :text_content,
        reason: "UNEQUAL_TEXT_CONTENTS"
      )

      expect(described_class.send(:empty_text_content_serialization_diff?, diff_node)).to be true
    end

    it "returns false when only one text is blank" do
      node1 = double("TextNode", value: "")
      node2 = double("TextNode", value: "text")

      diff_node = Canon::Diff::DiffNode.new(
        node1: node1,
        node2: node2,
        dimension: :text_content,
        reason: "UNEQUAL_TEXT_CONTENTS"
      )

      expect(described_class.send(:empty_text_content_serialization_diff?, diff_node)).to be false
    end
  end
end
