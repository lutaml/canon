# frozen_string_literal: true

require "spec_helper"
require "canon/pretty_printer/xml"

RSpec.describe Canon::PrettyPrinter::Xml do
  describe "#format" do
    let(:xml_content) do
      <<~XML
        <?xml version="1.0"?>
        <root><child>content</child></root>
      XML
    end

    context "with default options" do
      subject { described_class.new }

      it "formats XML with 2-space indentation" do
        result = subject.format(xml_content)
        expect(result).to include("  <child>")
      end

      it "preserves XML declaration" do
        result = subject.format(xml_content)
        expect(result).to match(/^<\?xml version/)
      end
    end

    context "with custom indent" do
      subject { described_class.new(indent: 4) }

      it "formats XML with 4-space indentation" do
        result = subject.format(xml_content)
        expect(result).to include("    <child>")
      end
    end

    context "with tab indentation" do
      subject { described_class.new(indent_type: "tab") }

      it "formats XML with tab indentation" do
        result = subject.format(xml_content)
        expect(result).to include("\t<child>")
      end
    end

    context "with complex XML" do
      subject { described_class.new(indent: 2) }

      let(:complex_xml) do
        <<~XML
          <?xml version="1.0"?>
          <root><level1><level2><level3>deep content</level3></level2></level1></root>
        XML
      end

      it "formats nested elements correctly" do
        result = subject.format(complex_xml)
        expect(result).to include("  <level1>")
        expect(result).to include("    <level2>")
        expect(result).to include("      <level3>")
      end
    end
  end


  # leptris#1564: the comparison pretty-printer receives HTML
  # producers' output (Asciidoctor: void elements, unclosed tags,
  # inline JS with bare <). The strict-XML parse must not kill the
  # comparison — HTML-shaped content routes to the engine's
  # tolerant HTML mode (moxml Context#parse_html, leptris >= 1.9.80
  # and nokogiri adapters alike). Malformed XML that is NOT
  # HTML-shaped stays loud.
  describe "HTML-tolerant fallback" do
    let(:html_content) do
      <<~HTML
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>t</title></head>
        <body><p>hello<br>world<img src="x.png"><ul><li>one<li>two</ul>
        <script>if (a < b) { c(); }</script></body></html>
      HTML
    end

    subject { described_class.new }

    it "formats HTML producers' output instead of raising" do
      expect { subject.format(html_content) }.not_to raise_error
    end

    it "emits the parsed HTML structure" do
      expect(subject.format(html_content)).to include("<title>t</title>")
    end

    it "keeps non-HTML malformed input loud" do
      expect { subject.format("<root><unclosed></root>") }
        .to raise_error(Moxml::ParseError)
    end
  end
end
