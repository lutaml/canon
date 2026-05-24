# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::XmlParsing do
  describe ".parse" do
    it "parses XML string into a document" do
      doc = described_class.parse("<root><child>text</child></root>")
      expect(doc).not_to be_nil
    end

    it "produces a document with a root element" do
      doc = described_class.parse("<root><child>text</child></root>")
      root = described_class.children(doc).first
      expect(root).not_to be_nil
    end
  end

  describe ".parse_fragment" do
    it "parses an XML fragment" do
      nodes = described_class.parse_fragment("<a/>")
      expect(nodes).not_to be_empty
    end
  end

  describe ".children" do
    it "returns child nodes" do
      doc = described_class.parse("<root><a/><b/></root>")
      root = described_class.children(doc).first
      children = described_class.children(root)
      expect(children.size).to eq(2)
    end
  end

  describe ".name" do
    it "returns the element name" do
      doc = described_class.parse("<root/>")
      root = described_class.children(doc).first
      expect(described_class.name(root)).to eq("root")
    end
  end

  describe ".text_content" do
    it "returns the text content" do
      doc = described_class.parse("<root>hello</root>")
      root = described_class.children(doc).first
      expect(described_class.text_content(root)).to eq("hello")
    end
  end

  describe ".element?" do
    it "returns true for element nodes" do
      doc = described_class.parse("<root/>")
      root = described_class.children(doc).first
      expect(described_class.element?(root)).to be true
    end
  end

  describe ".document?" do
    it "returns true for document objects" do
      doc = described_class.parse("<root/>")
      expect(described_class.document?(doc)).to be true
    end
  end

  describe ".xml_node?" do
    it "returns true for node objects" do
      doc = described_class.parse("<root/>")
      root = described_class.children(doc).first
      expect(described_class.xml_node?(root)).to be true
    end
  end
end
