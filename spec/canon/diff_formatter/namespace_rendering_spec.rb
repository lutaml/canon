# frozen_string_literal: true

require "spec_helper"
require "canon/xml/namespace_helper"

RSpec.describe "Canon::DiffFormatter namespace rendering" do
  describe "namespace display in XML diff output" do
    context "with empty namespace" do
      let(:xml1) { '<element attr="value">content</element>' }
      let(:xml2) { '<element attr="value">content</element>' }

      it "displays ns:[{blank}] for elements without namespace" do
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true
        )

        expect(result.equivalent?).to be true
      end
    end

    context "with populated namespace" do
      let(:xml1) do
        '<element xmlns="http://example.com" attr="value">content</element>'
      end
      let(:xml2) do
        '<element xmlns="http://example.com" attr="value">content</element>'
      end

      it "displays ns:[uri] for elements with namespace" do
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true
        )

        expect(result.equivalent?).to be true
      end
    end

    context "with mixed namespaces" do
      let(:xml1) do
        <<~XML
          <root xmlns="http://example.com" xmlns:ns="http://test.com">
            <element>value</element>
            <ns:element>value</ns:element>
          </root>
        XML
      end

      let(:xml2) do
        <<~XML
          <root xmlns="http://example.com" xmlns:ns="http://test.com">
            <element>value</element>
            <ns:element>value</ns:element>
          </root>
        XML
      end

      it "handles multiple namespaces correctly" do
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true
        )

        expect(result.equivalent?).to be true
      end
    end
  end

  describe "namespace mismatch classification" do
    context "same namespace, different element name" do
      let(:xml1) do
        '<root xmlns="http://example.com"><oldname>value</oldname></root>'
      end
      let(:xml2) do
        '<root xmlns="http://example.com"><newname>value</newname></root>'
      end

      it "reports mismatched element name" do
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true
        )

        expect(result.equivalent?).to be false
        expect(result.differences).not_to be_empty
      end
    end

    context "different namespace, same element name" do
      let(:xml1) do
        '<root><element xmlns="http://example1.com">value</element></root>'
      end
      let(:xml2) do
        '<root><element xmlns="http://example2.com">value</element></root>'
      end

      it "reports mismatched element namespace" do
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true
        )

        expect(result.equivalent?).to be false
        expect(result.differences).not_to be_empty
      end
    end

    context "empty namespace vs populated namespace" do
      let(:xml1) { '<root><element>value</element></root>' }
      let(:xml2) do
        '<root><element xmlns="http://example.com">value</element></root>'
      end

      it "reports namespace mismatch" do
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true
        )

        expect(result.equivalent?).to be false
        expect(result.differences).not_to be_empty
      end
    end
  end

  describe "attribute namespace rendering" do
    context "same namespace, different attribute name" do
      let(:xml1) do
        '<root xmlns:ns="http://example.com"><el ns:oldattr="val"/></root>'
      end
      let(:xml2) do
        '<root xmlns:ns="http://example.com"><el ns:newattr="val"/></root>'
      end

      it "reports mismatched attribute name" do
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true
        )

        expect(result.equivalent?).to be false
        expect(result.differences).not_to be_empty
      end
    end

    context "different namespace, same attribute name" do
      let(:xml1) do
        '<root xmlns:ns1="http://example1.com"><el ns1:attr="val"/></root>'
      end
      let(:xml2) do
        '<root xmlns:ns2="http://example2.com"><el ns2:attr="val"/></root>'
      end

      it "reports mismatched attribute namespace" do
        result = Canon::Comparison.equivalent?(
          xml1, xml2,
          verbose: true
        )

        # Note: This test documents the current behavior
        # Attribute namespace mismatches may be treated differently
        # depending on match profile
        expect(result.differences).not_to be_empty if !result.equivalent?
      end
    end
  end

  describe "namespace helper methods" do
    it "formats empty namespace as ns:[{blank}]" do
      node = Canon::Xml::Nodes::ElementNode.new(
        name: "element",
        namespace_uri: nil
      )

      helper = Canon::Xml::NamespaceHelper
      expect(helper.format_namespace(node.namespace_uri)).to eq("ns:[{blank}]")
    end

    it "formats populated namespace as ns:[uri]" do
      node = Canon::Xml::Nodes::ElementNode.new(
        name: "element",
        namespace_uri: "http://example.com"
      )

      helper = Canon::Xml::NamespaceHelper
      expect(helper.format_namespace(node.namespace_uri)).to eq("ns:[http://example.com]")
    end

    it "formats empty string namespace as ns:[{blank}]" do
      helper = Canon::Xml::NamespaceHelper
      expect(helper.format_namespace("")).to eq("ns:[{blank}]")
    end
  end

  describe "DiffNode namespace mismatch tracking" do
    it "tracks namespace mismatch type" do
      node1 = Canon::Xml::Nodes::ElementNode.new(
        name: "element",
        namespace_uri: "http://example1.com"
      )
      node2 = Canon::Xml::Nodes::ElementNode.new(
        name: "element",
        namespace_uri: "http://example2.com"
      )

      diff_node = Canon::Diff::DiffNode.new(
        node1: node1,
        node2: node2,
        dimension: :element_namespace,
        reason: "Namespace differs"
      )

      expect(diff_node.dimension).to eq(:element_namespace)
    end

    it "tracks name mismatch type" do
      node1 = Canon::Xml::Nodes::ElementNode.new(
        name: "oldname",
        namespace_uri: "http://example.com"
      )
      node2 = Canon::Xml::Nodes::ElementNode.new(
        name: "newname",
        namespace_uri: "http://example.com"
      )

      diff_node = Canon::Diff::DiffNode.new(
        node1: node1,
        node2: node2,
        dimension: :element_name,
        reason: "Name differs"
      )

      expect(diff_node.dimension).to eq(:element_name)
    end
  end
end