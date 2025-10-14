# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Comparison do
  describe ".equivalent?" do
    context "with HTML documents" do
      it "returns true for identical HTML" do
        html = "<html><body><p>Test</p></body></html>"
        expect(Canon::Comparison.equivalent?(html, html)).to be true
      end

      it "returns true when whitespace differs" do
        html1 = "<html><body><p>Test</p></body></html>"
        html2 = "<html>\n  <body>\n    <p>Test</p>\n  </body>\n</html>"
        expect(Canon::Comparison.equivalent?(html1, html2)).to be true
      end

      it "returns true when HTML comments differ" do
        html1 = "<html><body><!-- comment 1 --><p>Test</p></body></html>"
        html2 = "<html><body><!-- comment 2 --><p>Test</p></body></html>"
        expect(Canon::Comparison.equivalent?(html1, html2)).to be true
      end

      it "returns true when comments in style tags differ" do
        html1 = "<html><head><style><!-- --></style></head></html>"
        html2 = "<html><head><style><!-- p { color: red; } --></style></head></html>"
        expect(Canon::Comparison.equivalent?(html1, html2)).to be true
      end

      it "returns false when element structure differs" do
        html1 = "<html><body><p>Test</p></body></html>"
        html2 = "<html><body><div>Test</div></body></html>"
        expect(Canon::Comparison.equivalent?(html1, html2)).to be false
      end

      it "returns false when text content differs" do
        html1 = "<html><body><p>Test 1</p></body></html>"
        html2 = "<html><body><p>Test 2</p></body></html>"
        expect(Canon::Comparison.equivalent?(html1, html2)).to be false
      end
    end

    context "with XML documents" do
      it "returns true for identical XML" do
        xml = "<root><item>Test</item></root>"
        expect(Canon::Comparison.equivalent?(xml, xml)).to be true
      end

      it "returns true when whitespace differs" do
        xml1 = "<root><item>Test</item></root>"
        xml2 = "<root>\n  <item>Test</item>\n</root>"
        expect(Canon::Comparison.equivalent?(xml1, xml2)).to be true
      end

      it "returns false when element structure differs" do
        xml1 = "<root><item>Test</item></root>"
        xml2 = "<root><other>Test</other></root>"
        expect(Canon::Comparison.equivalent?(xml1, xml2)).to be false
      end
    end

    context "with options" do
      it "respects ignore_comments option" do
        html1 = "<html><body><!-- comment --><p>Test</p></body></html>"
        html2 = "<html><body><p>Test</p></body></html>"

        expect(Canon::Comparison.equivalent?(html1, html2,
                                             { ignore_comments: true })).to be true
        expect(Canon::Comparison.equivalent?(html1, html2,
                                             { ignore_comments: false })).to be false
      end

      it "respects collapse_whitespace option" do
        html1 = "<html><body><p>Test   Content</p></body></html>"
        html2 = "<html><body><p>Test Content</p></body></html>"

        expect(Canon::Comparison.equivalent?(html1, html2,
                                             { collapse_whitespace: true })).to be true
      end
    end
  end
end
