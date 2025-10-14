# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Comparison do
  describe ".equivalent?" do
    context "with HTML documents" do
      it "returns true for identical HTML" do
        html = "<html><body><p>Test</p></body></html>"
        expect(described_class.equivalent?(html, html)).to be true
      end

      it "returns true when whitespace differs" do
        html1 = "<html><body><p>Test</p></body></html>"
        html2 = "<html>\n  <body>\n    <p>Test</p>\n  </body>\n</html>"
        expect(described_class.equivalent?(html1, html2)).to be true
      end

      it "returns true when HTML comments differ" do
        html1 = "<html><body><!-- comment 1 --><p>Test</p></body></html>"
        html2 = "<html><body><!-- comment 2 --><p>Test</p></body></html>"
        expect(described_class.equivalent?(html1, html2)).to be true
      end

      it "returns true when comments in style tags differ" do
        html1 = "<html><head><style><!-- --></style></head></html>"
        html2 = "<html><head><style><!-- p { color: red; } --></style></head></html>"
        expect(described_class.equivalent?(html1, html2)).to be true
      end

      it "returns false when element structure differs" do
        html1 = "<html><body><p>Test</p></body></html>"
        html2 = "<html><body><div>Test</div></body></html>"
        expect(described_class.equivalent?(html1, html2)).to be false
      end

      it "returns false when text content differs" do
        html1 = "<html><body><p>Test 1</p></body></html>"
        html2 = "<html><body><p>Test 2</p></body></html>"
        expect(described_class.equivalent?(html1, html2)).to be false
      end
    end

    context "with XML documents" do
      it "returns true for identical XML" do
        xml = "<root><item>Test</item></root>"
        expect(described_class.equivalent?(xml, xml)).to be true
      end

      it "returns true when whitespace differs" do
        xml1 = "<root><item>Test</item></root>"
        xml2 = "<root>\n  <item>Test</item>\n</root>"
        expect(described_class.equivalent?(xml1, xml2)).to be true
      end

      it "returns false when element structure differs" do
        xml1 = "<root><item>Test</item></root>"
        xml2 = "<root><other>Test</other></root>"
        expect(described_class.equivalent?(xml1, xml2)).to be false
      end
    end

    context "with options" do
      it "respects ignore_comments option" do
        html1 = "<html><body><!-- comment --><p>Test</p></body></html>"
        html2 = "<html><body><p>Test</p></body></html>"

        expect(described_class.equivalent?(html1, html2,
                                           { ignore_comments: true })).to be true
        expect(described_class.equivalent?(html1, html2,
                                           { ignore_comments: false })).to be false
      end

      it "respects collapse_whitespace option" do
        html1 = "<html><body><p>Test   Content</p></body></html>"
        html2 = "<html><body><p>Test Content</p></body></html>"

        expect(described_class.equivalent?(html1, html2,
                                           { collapse_whitespace: true })).to be true
      end
    end

    context "with verbose mode" do
      it "returns empty array for equivalent HTML documents" do
        html1 = "<html><body><p>Test</p></body></html>"
        html2 = "<html><body><p>Test</p></body></html>"

        result = described_class.equivalent?(html1, html2,
                                             { verbose: true })
        expect(result).to be_an(Array)
        expect(result).to be_empty
      end

      it "returns array of differences for different element names" do
        html1 = "<html><body><p>Test</p></body></html>"
        html2 = "<html><body><div>Test</div></body></html>"

        result = described_class.equivalent?(html1, html2,
                                             { verbose: true })
        expect(result).to be_an(Array)
        expect(result).not_to be_empty
        expect(result.first).to have_key(:node1)
        expect(result.first).to have_key(:node2)
        expect(result.first).to have_key(:diff1)
        expect(result.first).to have_key(:diff2)
        expect(result.first[:diff1]).to eq(Canon::Comparison::UNEQUAL_ELEMENTS)
      end

      it "returns array of differences for different text content" do
        html1 = "<html><body><p>Test 1</p></body></html>"
        html2 = "<html><body><p>Test 2</p></body></html>"

        result = described_class.equivalent?(html1, html2,
                                             { verbose: true })
        expect(result).to be_an(Array)
        expect(result).not_to be_empty
        expect(result.first[:diff1]).to eq(Canon::Comparison::UNEQUAL_TEXT_CONTENTS)
      end

      it "returns array of differences for different attributes" do
        html1 = '<html><body><p class="foo">Test</p></body></html>'
        html2 = '<html><body><p class="bar">Test</p></body></html>'

        result = described_class.equivalent?(html1, html2,
                                             { verbose: true })
        expect(result).to be_an(Array)
        expect(result).not_to be_empty
        expect(result.first[:diff1]).to eq(Canon::Comparison::UNEQUAL_ATTRIBUTES)
      end

      it "returns array of differences for missing nodes" do
        html1 = "<html><body><p>Test</p><div>Extra</div></body></html>"
        html2 = "<html><body><p>Test</p></body></html>"

        result = described_class.equivalent?(html1, html2,
                                             { verbose: true })
        expect(result).to be_an(Array)
        expect(result).not_to be_empty
        expect(result.first[:diff1]).to eq(Canon::Comparison::MISSING_NODE)
      end

      it "returns array of differences for missing attributes" do
        html1 = '<html><body><p class="foo" id="bar">Test</p></body></html>'
        html2 = '<html><body><p class="foo">Test</p></body></html>'

        result = described_class.equivalent?(html1, html2,
                                             { verbose: true })
        expect(result).to be_an(Array)
        expect(result).not_to be_empty
        expect(result.first[:diff1]).to eq(Canon::Comparison::MISSING_ATTRIBUTE)
      end

      it "returns multiple differences when multiple things differ" do
        html1 = '<html><body><p class="foo">Test 1</p><div>Extra</div></body></html>'
        html2 = '<html><body><p class="bar">Test 2</p></body></html>'

        result = described_class.equivalent?(html1, html2,
                                             { verbose: true })
        expect(result).to be_an(Array)
        expect(result.length).to be >= 1
      end

      it "returns empty array for equivalent XML documents" do
        xml1 = "<root><item>Test</item></root>"
        xml2 = "<root><item>Test</item></root>"

        result = described_class.equivalent?(xml1, xml2,
                                             { verbose: true })
        expect(result).to be_an(Array)
        expect(result).to be_empty
      end

      it "returns array of differences for different XML elements" do
        xml1 = "<root><item>Test</item></root>"
        xml2 = "<root><other>Test</other></root>"

        result = described_class.equivalent?(xml1, xml2,
                                             { verbose: true })
        expect(result).to be_an(Array)
        expect(result).not_to be_empty
        expect(result.first[:diff1]).to eq(Canon::Comparison::UNEQUAL_ELEMENTS)
      end

      it "respects other options when in verbose mode" do
        html1 = "<html><body><!-- comment --><p>Test</p></body></html>"
        html2 = "<html><body><p>Test</p></body></html>"

        # With ignore_comments: true, should return empty array
        result = described_class.equivalent?(html1, html2,
                                             { verbose: true, ignore_comments: true })
        expect(result).to be_an(Array)
        expect(result).to be_empty

        # With ignore_comments: false, should return differences
        result = described_class.equivalent?(html1, html2,
                                             { verbose: true, ignore_comments: false })
        expect(result).to be_an(Array)
        expect(result).not_to be_empty
      end
    end
  end
end
