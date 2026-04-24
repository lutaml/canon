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

      it "returns true when whitespace differs (when using :ignore)" do
        xml1 = "<root><item>Test</item></root>"
        xml2 = "<root>\n  <item>Test</item>\n</root>"

        # rubocop:disable Layout/LineLength
        expect(described_class.equivalent?(xml1, xml2, match: { structural_whitespace: :ignore })).to be true
        # rubocop:enable Layout/LineLength
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

      it "returns ComparisonResult with differences " \
         "for different element names" do
        xml1 = "<root><item>Test</item></root>"
        xml2 = "<root><other>Test</other></root>"

        result = described_class.equivalent?(xml1, xml2, { verbose: true })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false
        expect(result.differences.first.dimension).to eq(:element_structure)
      end

      it "returns ComparisonResult with differences " \
         "for different text content" do
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
                                           { match: { comments: :ignore } }))
          .to be true
      end

      it "respects text_content match option" do
        xml1 = "<root><item>Test   Content</item></root>"
        xml2 = "<root><item>Test Content</item></root>"

        # XML defaults: text_content is strict, so should be false
        expect(described_class.equivalent?(xml1, xml2)).to be false

        # With normalize text_content, should be true
        expect(
          described_class.equivalent?(xml1, xml2,
                                      { match: { text_content: :normalize } }),
        ).to be true
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

      it "reports namespace differences as deleted/inserted " \
         "via ElementMatcher" do
        # ElementMatcher treats elements with different namespaces
        # as separate elements. With whitespace stripped (XML default),
        # ElementMatcher is used and reports namespace differences as
        # deleted/inserted (2 differences) rather than a modification.
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

        # Elements with different namespaces are detected as different
        # ElementMatcher reports them as deleted/inserted (2 differences)
        expect(result.differences.length).to eq(2)
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

    # https://github.com/lutaml/canon/issues/110
    context "space vs NBSP between inline elements (issue #110)" do
      it "detects space vs NBSP as different with spec_friendly (default whitespace_type: :strict)" do
        input = <<~XML
          <semx element="eref" source="_">
             <fmt-xref type="inline" target="ISO712"><span class="stdpublisher">ISO</span> <span class="stddocNumber">712</span>, Appendice 7</fmt-xref>
          </semx>
        XML
        output = <<~XML
          <semx element="eref" source="_">
             <fmt-xref type="inline" target="ISO712"><span class="stdpublisher">ISO</span>&#xa0;<span class="stddocNumber">712</span>, Appendice 7</fmt-xref>
          </semx>
        XML

        result = described_class.equivalent?(input, output,
                                             match_profile: :spec_friendly,
                                             verbose: true)
        expect(result.equivalent?).to be false
        # Should report the difference cleanly, not garbled phantom nodes
        expect(result.differences.size).to be >= 1
        # Reason must never contain raw Ruby object inspect output
        result.differences.each do |diff|
          expect(diff.reason).not_to match(/#<Canon::Xml::Nodes/)
          expect(diff.reason).not_to match(/#<Canon::Diff/)
        end
      end

      it "treats space and NBSP as equivalent with whitespace_type: :normalize" do
        input = <<~XML
          <semx element="eref" source="_">
             <fmt-xref type="inline" target="ISO712"><span class="stdpublisher">ISO</span> <span class="stddocNumber">712</span>, Appendice 7</fmt-xref>
          </semx>
        XML
        output = <<~XML
          <semx element="eref" source="_">
             <fmt-xref type="inline" target="ISO712"><span class="stdpublisher">ISO</span>&#xa0;<span class="stddocNumber">712</span>, Appendice 7</fmt-xref>
          </semx>
        XML

        result = described_class.equivalent?(input, output,
                                             match_profile: :spec_friendly,
                                             match: { whitespace_type: :normalize },
                                             verbose: true)
        expect(result.equivalent?).to be true
        expect(result.differences.size).to eq(0)
      end

      it "detects letter differences correctly (baseline)" do
        input = <<~XML
          <semx element="eref" source="_">
             <fmt-xref type="inline" target="ISO712"><span class="stdpublisher">ISO</span>a<span class="stddocNumber">712</span>, Appendice 7</fmt-xref>
          </semx>
        XML
        output = <<~XML
          <semx element="eref" source="_">
             <fmt-xref type="inline" target="ISO712"><span class="stdpublisher">ISO</span>b<span class="stddocNumber">712</span>, Appendice 7</fmt-xref>
          </semx>
        XML

        result = described_class.equivalent?(input, output,
                                             match_profile: :spec_friendly,
                                             verbose: true)
        expect(result.equivalent?).to be false
        expect(result.differences.size).to eq(1)
        # Reason must never contain raw Ruby object inspect output
        result.differences.each do |diff|
          expect(diff.reason).not_to match(/#<Canon::Xml::Nodes/)
          expect(diff.reason).not_to match(/#<Canon::Diff/)
        end
      end
    end
  end
end
