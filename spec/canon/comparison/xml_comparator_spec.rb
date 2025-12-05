# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Comparison::XmlComparator do
  describe ".equivalent?" do
    context "with identical XML" do
      it "returns true for simple identical XML" do
        xml1 = "<root><item>Test</item></root>"
        xml2 = "<root><item>Test</item></root>"

        expect(described_class.equivalent?(xml1, xml2)).to be true
      end

      it "returns true when whitespace differs" do
        xml1 = "<root><item>Test</item></root>"
        xml2 = "<root>\n  <item>Test</item>\n</root>"

        expect(described_class.equivalent?(xml1, xml2)).to be true
      end
    end

    context "with different XML" do
      it "returns false when element names differ" do
        xml1 = "<root><item>Test</item></root>"
        xml2 = "<root><other>Test</other></root>"

        expect(described_class.equivalent?(xml1, xml2)).to be false
      end

      it "returns false when text content differs" do
        xml1 = "<root><item>Test 1</item></root>"
        xml2 = "<root><item>Test 2</item></root>"

        expect(described_class.equivalent?(xml1, xml2)).to be false
      end

      it "returns false when attributes differ" do
        xml1 = '<root><item id="1">Test</item></root>'
        xml2 = '<root><item id="2">Test</item></root>'

        expect(described_class.equivalent?(xml1, xml2)).to be false
      end
    end

    context "with verbose mode" do
      it "returns ComparisonResult with no differences for equivalent XML" do
        xml1 = "<root><item>Test</item></root>"
        xml2 = "<root><item>Test</item></root>"

        result = described_class.equivalent?(xml1, xml2, { verbose: true })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).to be_empty
        expect(result.equivalent?).to be true
      end

      it "returns ComparisonResult with differences for different element names" do
        xml1 = "<root><item>Test</item></root>"
        xml2 = "<root><other>Test</other></root>"

        result = described_class.equivalent?(xml1, xml2, { verbose: true })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false
        expect(result.differences.first.dimension).to eq(:text_content)
      end

      it "returns ComparisonResult with differences for different text content" do
        xml1 = "<root><item>Test 1</item></root>"
        xml2 = "<root><item>Test 2</item></root>"

        result = described_class.equivalent?(xml1, xml2, { verbose: true })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false
        diff = result.differences.first
        expect(diff).to be_a(Canon::Diff::DiffNode)
        expect(diff.dimension).to eq(:text_content)
      end

      it "returns ComparisonResult with differences for different attributes" do
        xml1 = '<root id="1">Content</root>'
        xml2 = '<root id="2">Content</root>'

        result = described_class.equivalent?(xml1, xml2, verbose: true)
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false
        diff = result.differences.first
        expect(diff).to be_a(Canon::Diff::DiffNode)
        expect(diff.dimension).to eq(:attribute_values)
      end
    end

    context "with options" do
      it "respects comments match option" do
        xml1 = "<root><!-- comment --><item>Test</item></root>"
        xml2 = "<root><item>Test</item></root>"

        # XML defaults: comments are strict, so should be false
        expect(described_class.equivalent?(xml1, xml2)).to be false

        # With ignore comments, should be true
        expect(described_class.equivalent?(xml1, xml2,
                                           { match: { comments: :ignore } })).to be true
      end

      it "respects text_content match option" do
        xml1 = "<root><item>Test   Content</item></root>"
        xml2 = "<root><item>Test Content</item></root>"

        # XML defaults: text_content is strict, so should be false
        expect(described_class.equivalent?(xml1, xml2)).to be false

        # With normalize text_content, should be true
        expect(described_class.equivalent?(xml1, xml2,
                                           { match: { text_content: :normalize } })).to be true
      end
    end

    context "with namespace handling" do
      it "detects different namespace URIs on same element name" do
        xml1 = '<root xmlns="http://example.org/ns1"><child>content</child></root>'
        xml2 = '<root xmlns="http://example.org/ns2"><child>content</child></root>'

        expect(described_class.equivalent?(xml1, xml2)).to be false
      end

      it "returns true for elements with same namespace URI" do
        xml1 = '<root xmlns="http://example.org/ns1"><child>content</child></root>'
        xml2 = '<root xmlns="http://example.org/ns1"><child>content</child></root>'

        expect(described_class.equivalent?(xml1, xml2)).to be true
      end

      it "detects namespace inheritance differences" do
        # XML1: child inherits parent namespace
        xml1 = <<~XML
          <root xmlns="http://example.org/ns1">
            <child>content</child>
          </root>
        XML

        # XML2: child explicitly declares different namespace
        xml2 = <<~XML
          <root xmlns="http://example.org/ns1">
            <child xmlns="http://example.org/ns2">content</child>
          </root>
        XML

        expect(described_class.equivalent?(xml1, xml2)).to be false
      end

      it "reports namespace differences as deleted/inserted via ElementMatcher" do
        # ElementMatcher treats elements with different namespaces as separate elements
        xml1 = <<~XML
          <root>
            <child xmlns="http://example.org/ns1">content</child>
          </root>
        XML

        xml2 = <<~XML
          <root>
            <child xmlns="http://example.org/ns2">content</child>
          </root>
        XML

        result = described_class.equivalent?(xml1, xml2, verbose: true)

        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false

        # Elements with different namespaces are treated as deleted/inserted
        # This is correct behavior - they ARE different elements
        expect(result.differences.length).to eq(2) # One deleted, one inserted
      end

      it "handles elements with no namespace vs elements with namespace" do
        xml1 = "<root><child>content</child></root>"
        xml2 = '<root xmlns="http://example.org/ns1"><child>content</child></root>'

        expect(described_class.equivalent?(xml1, xml2)).to be false
      end

      it "correctly compares nested namespaces" do
        xml1 = <<~XML
          <root xmlns="http://example.org/ns1">
            <parent>
              <child xmlns="http://example.org/ns2">content</child>
            </parent>
          </root>
        XML

        xml2 = <<~XML
          <root xmlns="http://example.org/ns1">
            <parent>
              <child xmlns="http://example.org/ns2">content</child>
            </parent>
          </root>
        XML

        expect(described_class.equivalent?(xml1, xml2)).to be true
      end

      it "detects when nested element has wrong namespace" do
        xml1 = <<~XML
          <root xmlns="http://example.org/ns1">
            <parent>
              <child xmlns="http://example.org/ns2">content</child>
            </parent>
          </root>
        XML

        xml2 = <<~XML
          <root xmlns="http://example.org/ns1">
            <parent>
              <child xmlns="http://example.org/ns3">content</child>
            </parent>
          </root>
        XML

        expect(described_class.equivalent?(xml1, xml2)).to be false
      end
    end
  end
end
