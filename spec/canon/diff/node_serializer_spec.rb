# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Diff::NodeSerializer do
  describe ".serialize" do
    context "with Nokogiri HTML nodes" do
      it "serializes HTML element" do
        html = "<span id='test'>Text</span>"
        doc = Nokogiri::HTML4.fragment(html)
        node = doc.children.first

        serialized = described_class.serialize(node)

        expect(serialized).to include("<span")
        expect(serialized).to include('id="test"')
      end

      it "serializes HTML text node" do
        html = "<div>Text content</div>"
        doc = Nokogiri::HTML4.fragment(html)
        text_node = doc.children.first.children.first

        serialized = described_class.serialize(text_node)

        expect(serialized).to eq("Text content")
      end

      it "serializes HTML document" do
        html = "<html><body><div>Content</div></body></html>"
        doc = Nokogiri::HTML4.parse(html)

        serialized = described_class.serialize(doc)

        expect(serialized).to include("<html")
      end

      it "handles nil node" do
        serialized = described_class.serialize(nil)
        expect(serialized).to eq("")
      end
    end

    context "with Nokogiri XML nodes" do
      it "serializes XML element" do
        xml = "<root><element attr='value'>Text</element></root>"
        doc = Nokogiri::XML(xml)
        element = doc.at_css("element")

        serialized = described_class.serialize(element)

        expect(serialized).to include("<element")
        expect(serialized).to include('attr="value"')
      end

      it "serializes XML document" do
        xml = "<?xml version='1.0'?><root><item>Text</item></root>"
        doc = Nokogiri::XML(xml)

        serialized = described_class.serialize(doc)

        expect(serialized).to include("<root")
      end
    end

    context "with custom node objects" do
      it "handles nodes with to_html method" do
        # Use a simple struct that implements to_html
        node = Struct.new(:content).new("<custom>Serialized</custom>")
        def node.to_html
          content
        end

        serialized = described_class.serialize(node)

        expect(serialized).to eq("<custom>Serialized</custom>")
      end

      it "handles nodes with to_xml method (when to_html is not available)" do
        node = Struct.new(:content).new("<custom>Serialized</custom>")
        def node.to_xml
          content
        end

        serialized = described_class.serialize(node)

        expect(serialized).to eq("<custom>Serialized</custom>")
      end

      it "falls back to to_s for other nodes" do
        node = Struct.new(:content).new("plain text")
        def node.to_s
          content
        end

        serialized = described_class.serialize(node)

        expect(serialized).to eq("plain text")
      end
    end
  end

  describe ".extract_attributes" do
    context "with Canon::Xml::Nodes::ElementNode" do
      it "extracts all attributes" do
        xml = "<div lang='en' id='test' class='container'>Text</div>"
        node = Canon::Xml::DataModel.from_xml(xml)
        element = node.children.first

        attrs = described_class.extract_attributes(element)

        expect(attrs).to be_a(Hash)
        expect(attrs["lang"]).to eq("en")
        expect(attrs["id"]).to eq("test")
        expect(attrs["class"]).to eq("container")
      end

      it "returns empty hash for element with no attributes" do
        xml = "<div>Text</div>"
        node = Canon::Xml::DataModel.from_xml(xml)
        element = node.children.first

        attrs = described_class.extract_attributes(element)

        expect(attrs).to eq({})
      end
    end

    context "with Nokogiri HTML nodes" do
      it "extracts attributes from HTML element" do
        html = "<span lang='en-US' id='test'>Text</span>"
        doc = Nokogiri::HTML4.fragment(html)
        node = doc.children.first

        attrs = described_class.extract_attributes(node)

        expect(attrs).to be_a(Hash)
        expect(attrs["lang"]).to eq("en-US")
        expect(attrs["id"]).to eq("test")
      end

      it "extracts attributes from XML element" do
        xml = "<element attr1='value1' attr2='value2'/>"
        doc = Nokogiri::XML(xml)
        node = doc.root

        attrs = described_class.extract_attributes(node)

        expect(attrs).to be_a(Hash)
        expect(attrs["attr1"]).to eq("value1")
        expect(attrs["attr2"]).to eq("value2")
      end

      it "handles nil node" do
        attrs = described_class.extract_attributes(nil)
        expect(attrs).to eq({})
      end
    end

    context "attribute normalization" do
      it "normalizes attribute values to strings" do
        html = "<div id='123'>Text</div>"
        doc = Nokogiri::HTML4.fragment(html)
        node = doc.children.first

        attrs = described_class.extract_attributes(node)

        expect(attrs["id"]).to be_a(String)
        expect(attrs["id"]).to eq("123")
      end

      it "handles special characters in attribute values" do
        xml = "<div attr='value with &quot;quotes&quot;'>Text</div>"
        doc = Nokogiri::XML.parse(xml)
        node = doc.root

        attrs = described_class.extract_attributes(node)

        expect(attrs["attr"]).to be_a(String)
        expect(attrs["attr"]).to include("value")
      end
    end
  end
end
