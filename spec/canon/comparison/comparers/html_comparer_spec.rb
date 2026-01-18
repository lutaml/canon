# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Comparison::HtmlComparer do
  describe ".compare" do
    context "with identical HTML documents" do
      let(:html1) { "<html><body><p>content</p></body></html>" }
      let(:html2) { "<html><body><p>content</p></body></html>" }

      it "returns true for equivalent documents" do
        result = described_class.compare(html1, html2)
        expect(result).to be true
      end
    end

    context "with different HTML documents" do
      let(:html1) { "<html><body><p>content1</p></body></html>" }
      let(:html2) { "<html><body><p>content2</p></body></html>" }

      it "returns false for different documents" do
        result = described_class.compare(html1, html2)
        expect(result).to be false
      end
    end

    context "with whitespace differences" do
      let(:html1) { "<html><body><p>content  here</p></body></html>" }
      let(:html2) { "<html><body><p>content here</p></body></html>" }

      it "treats whitespace differences as equivalent with :rendered profile" do
        result = described_class.compare(html1, html2, match_profile: :rendered)
        expect(result).to be true
      end
    end

    context "with verbose option" do
      let(:html1) { "<html><body><p>content1</p></body></html>" }
      let(:html2) { "<html><body><p>content2</p></body></html>" }

      it "returns ComparisonResult with differences" do
        result = described_class.compare(html1, html2, verbose: true)
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
      end
    end
  end

  describe ".serialize_document" do
    context "with Canon::Xml::Node" do
      it "serializes to HTML string" do
        # Parse HTML using the proper API
        node = Canon::Html::DataModel.parse(
          "<html><body><p>content</p></body></html>", version: :html5
        )
        result = described_class.serialize_document(node)
        expect(result).to be_a(String)
      end
    end

    context "with Nokogiri HTML node" do
      it "calls to_html method" do
        node = Nokogiri::HTML("<html><body><p>content</p></body></html>")
        result = described_class.serialize_document(node)
        expect(result).to be_a(String)
      end
    end
  end
end
