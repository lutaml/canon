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
      let(:complex_xml) do
        <<~XML
          <?xml version="1.0"?>
          <root><level1><level2><level3>deep content</level3></level2></level1></root>
        XML
      end

      subject { described_class.new(indent: 2) }

      it "formats nested elements correctly" do
        result = subject.format(complex_xml)
        expect(result).to include("  <level1>")
        expect(result).to include("    <level2>")
        expect(result).to include("      <level3>")
      end
    end
  end
end
