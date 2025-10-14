# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Formatters::HtmlFormatter do
  describe ".format" do
    context "with HTML5" do
      it "formats simple HTML" do
        html = "<html><body><p>test</p></body></html>"
        result = described_class.format(html)
        expect(result).to include("<p>test</p>")
      end

      it "preserves structure" do
        html = "<div><span>text</span></div>"
        result = described_class.format(html)
        expect(result).to include("<div>")
        expect(result).to include("<span>")
      end
    end

    context "with XHTML" do
      it "formats XHTML correctly" do
        xhtml = '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>test</p></body></html>'
        result = described_class.format(xhtml)
        expect(result).to include("<p>test</p>")
      end
    end

    context "with fixture files" do
      let(:html_fixture) do
        File.read("spec/fixtures/html/isodoc-figures-spec-1-html.html")
      end

      let(:word_html_fixture) do
        File.read("spec/fixtures/html/isodoc-figures-spec-1-word.html")
      end

      it "formats HTML fixture without errors" do
        expect { described_class.format(html_fixture) }.not_to raise_error
      end

      it "formats Word HTML fixture without errors" do
        expect { described_class.format(word_html_fixture) }.not_to raise_error
      end

      it "preserves structure in HTML fixture" do
        result = described_class.format(html_fixture)
        expect(result).to include("figure")
        expect(result).to include("FigureTitle")
      end

      it "preserves structure in Word HTML fixture" do
        result = described_class.format(word_html_fixture)
        expect(result).to include("figure")
        expect(result).to include("FigureTitle")
      end
    end

    context "with cleanup spec fixtures" do
      (1..5).each do |i|
        it "formats isodoc-cleanup-spec-#{i}.html without errors" do
          html = File.read("spec/fixtures/html/isodoc-cleanup-spec-#{i}.html")
          expect { described_class.format(html) }.not_to raise_error
        end
      end
    end
  end

  describe ".parse" do
    it "parses HTML5" do
      html = "<html><body><p>test</p></body></html>"
      doc = described_class.parse(html)
      expect(doc).to be_a(Nokogiri::HTML5::Document)
    end

    it "parses XHTML as XML" do
      xhtml = '<html xmlns="http://www.w3.org/1999/xhtml"><body><p>test</p></body></html>'
      doc = described_class.parse(xhtml)
      expect(doc).to be_a(Nokogiri::XML::Document)
    end

    it "preserves content" do
      html = "<div><p>test content</p></div>"
      doc = described_class.parse(html)
      expect(doc.text).to include("test content")
    end
  end

  describe "roundtrip" do
    it "preserves information through parse and format cycle" do
      html = "<html><body><div><p>test</p></div></body></html>"
      doc = described_class.parse(html)
      formatted = described_class.format(html)
      doc2 = described_class.parse(formatted)

      expect(doc.text).to eq(doc2.text)
    end

    it "works with fixture files" do
      html = File.read("spec/fixtures/html/isodoc-figures-spec-1-html.html")
      doc1 = described_class.parse(html)
      formatted = described_class.format(html)
      doc2 = described_class.parse(formatted)

      # Content should be preserved (normalize whitespace for comparison)
      expect(doc1.text.gsub(/\s+/,
                            " ").strip).to eq(doc2.text.gsub(/\s+/, " ").strip)
    end
  end
end
