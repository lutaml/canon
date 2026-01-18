# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Comparison::XmlComparer do
  describe ".compare" do
    context "with identical XML documents" do
      let(:xml1) { "<root><child>content</child></root>" }
      let(:xml2) { "<root><child>content</child></root>" }

      it "returns true for equivalent documents" do
        result = described_class.compare(xml1, xml2)
        expect(result).to be true
      end
    end

    context "with different XML documents" do
      let(:xml1) { "<root><child>content1</child></root>" }
      let(:xml2) { "<root><child>content2</child></root>" }

      it "returns false for different documents" do
        result = described_class.compare(xml1, xml2)
        expect(result).to be false
      end
    end

    context "with verbose option" do
      let(:xml1) { "<root><child>content1</child></root>" }
      let(:xml2) { "<root><child>content2</child></root>" }

      it "returns ComparisonResult with differences" do
        result = described_class.compare(xml1, xml2, verbose: true)
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
      end
    end
  end

  describe ".serialize_document" do
    context "with Canon::Xml::Node" do
      it "serializes to XML string" do
        # Parse XML using the proper API
        node = Canon::Xml::DataModel.parse("<root><child>content</child></root>")
        result = described_class.serialize_document(node)
        expect(result).to be_a(String)
      end
    end

    context "with Nokogiri node" do
      it "calls to_xml method" do
        node = Nokogiri::XML("<root><child>content</child></root>")
        result = described_class.serialize_document(node)
        expect(result).to be_a(String)
      end
    end
  end
end
