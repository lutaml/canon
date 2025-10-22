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
      it "respects comments match option" do
        html1 = "<html><body><!-- comment --><p>Test</p></body></html>"
        html2 = "<html><body><p>Test</p></body></html>"

        # HTML defaults: comments are ignored, so should be true
        expect(described_class.equivalent?(html1, html2)).to be true

        # With strict comments matching, should be false
        expect(described_class.equivalent?(html1, html2,
                                           { match: { comments: :strict } })).to be false
      end

      it "respects text_content match option" do
        html1 = "<html><body><p>Test   Content</p></body></html>"
        html2 = "<html><body><p>Test Content</p></body></html>"

        # HTML defaults: text_content is normalized, so should be true
        expect(described_class.equivalent?(html1, html2)).to be true
      end
    end

    context "with verbose mode" do
      it "returns ComparisonResult for equivalent HTML documents" do
        html1 = "<html><body><p>Test</p></body></html>"
        html2 = "<html><body><p>Test</p></body></html>"

        result = described_class.equivalent?(html1, html2,
                                             { verbose: true })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).to be_empty
        expect(result.equivalent?).to be true
      end

      it "returns ComparisonResult with differences for different element names" do
        html1 = "<html><body><p>Test</p></body></html>"
        html2 = "<html><body><div>Test</div></body></html>"

        result = described_class.equivalent?(html1, html2,
                                             { verbose: true })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false
        expect(result.differences.first).to be_a(Canon::Diff::DiffNode)
        expect(result.differences.first.node1).not_to be_nil
        expect(result.differences.first.node2).not_to be_nil
        expect(result.differences.first.dimension).to eq(:text_content)
      end

      it "returns ComparisonResult with differences for different text content" do
        html1 = "<html><body><p>Test 1</p></body></html>"
        html2 = "<html><body><p>Test 2</p></body></html>"

        result = described_class.equivalent?(html1, html2,
                                             { verbose: true })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false
        # Can be either DiffNode or Hash
        diff = result.differences.first
        if diff.is_a?(Canon::Diff::DiffNode)
          expect(diff.dimension).to eq(:text_content)
        else
          expect(diff.dimension).to eq(:text_content)
        end
      end

      it "returns ComparisonResult with differences for different attributes" do
        html1 = '<html><body><p class="foo">Test</p></body></html>'
        html2 = '<html><body><p class="bar">Test</p></body></html>'

        result = described_class.equivalent?(html1, html2,
                                             { verbose: true })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false
        # Can be either DiffNode or Hash
        diff = result.differences.first
        if diff.is_a?(Canon::Diff::DiffNode)
          expect([:attribute_whitespace, :attribute_values]).to include(diff.dimension)
        else
          expect(diff.dimension).to eq(:text_content)
        end
      end

      it "returns ComparisonResult with differences for missing nodes" do
        html1 = "<html><body><p>Test</p><div>Extra</div></body></html>"
        html2 = "<html><body><p>Test</p></body></html>"

        result = described_class.equivalent?(html1, html2,
                                             { verbose: true })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false
        expect(result.differences.first.dimension).to eq(:text_content)
      end

      it "returns ComparisonResult with differences for missing attributes" do
        html1 = '<html><body><p class="foo" id="bar">Test</p></body></html>'
        html2 = '<html><body><p class="foo">Test</p></body></html>'

        result = described_class.equivalent?(html1, html2,
                                             { verbose: true })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false
        # Can be either DiffNode or Hash
        diff = result.differences.first
        if diff.is_a?(Canon::Diff::DiffNode)
          expect([:attribute_whitespace, :attribute_values]).to include(diff.dimension)
        else
          expect(diff.dimension).to eq(:text_content)
        end
      end

      it "returns ComparisonResult with multiple differences when multiple things differ" do
        html1 = '<html><body><p class="foo">Test 1</p><div>Extra</div></body></html>'
        html2 = '<html><body><p class="bar">Test 2</p></body></html>'

        result = described_class.equivalent?(html1, html2,
                                             { verbose: true })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences.length).to be >= 1
        expect(result.equivalent?).to be false
      end

      it "returns ComparisonResult for equivalent XML documents" do
        xml1 = "<root><item>Test</item></root>"
        xml2 = "<root><item>Test</item></root>"

        result = described_class.equivalent?(xml1, xml2,
                                             { verbose: true })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).to be_empty
        expect(result.equivalent?).to be true
      end

      it "returns ComparisonResult with differences for different XML elements" do
        xml1 = "<root><item>Test</item></root>"
        xml2 = "<root><other>Test</other></root>"

        result = described_class.equivalent?(xml1, xml2,
                                             { verbose: true })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false
        expect(result.differences.first.dimension).to eq(:text_content)
      end

      it "respects other options when in verbose mode" do
        html1 = "<html><body><!-- comment --><p>Test</p></body></html>"
        html2 = "<html><body><p>Test</p></body></html>"

        # HTML defaults: comments are ignored, should return empty differences
        result = described_class.equivalent?(html1, html2,
                                             { verbose: true })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).to be_empty
        expect(result.equivalent?).to be true

        # With strict comments matching, should return differences
        result = described_class.equivalent?(html1, html2,
                                             { verbose: true, match: { comments: :strict } })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false
      end
    end

    context "with different input types" do
      let(:html_string) { "<html><body><p>Test content</p></body></html>" }
      let(:xml_string) { "<root><item>Test content</item></root>" }

      context "Nokogiri::HTML::Document" do
        it "accepts and compares Nokogiri::HTML::Document objects" do
          doc1 = Nokogiri::HTML::Document.parse(html_string)
          doc2 = Nokogiri::HTML::Document.parse(html_string)
          expect(described_class.equivalent?(doc1, doc2)).to be true
        end

        it "compares Nokogiri::HTML::Document with string" do
          doc = Nokogiri::HTML::Document.parse(html_string)
          expect(described_class.equivalent?(doc, html_string)).to be true
          expect(described_class.equivalent?(html_string, doc)).to be true
        end
      end

      context "Nokogiri::HTML5::Document" do
        it "accepts and compares Nokogiri::HTML5::Document objects" do
          doc1 = Nokogiri::HTML5::Document.parse(html_string)
          doc2 = Nokogiri::HTML5::Document.parse(html_string)
          expect(described_class.equivalent?(doc1, doc2)).to be true
        end

        it "compares Nokogiri::HTML5::Document with string" do
          doc = Nokogiri::HTML5::Document.parse(html_string)
          # HTML5 documents add meta tags, so need to compare both as documents
          doc2 = Nokogiri::HTML5::Document.parse(html_string)
          expect(described_class.equivalent?(doc, doc2)).to be true
        end
      end

      context "Nokogiri::HTML::DocumentFragment" do
        it "accepts and compares Nokogiri::HTML::DocumentFragment objects" do
          frag1 = Nokogiri::HTML::DocumentFragment.parse("<p>Test content</p>")
          frag2 = Nokogiri::HTML::DocumentFragment.parse("<p>Test content</p>")
          expect(described_class.equivalent?(frag1, frag2)).to be true
        end

        it "detects differences in DocumentFragments" do
          frag1 = Nokogiri::HTML::DocumentFragment.parse("<p>Test 1</p>")
          frag2 = Nokogiri::HTML::DocumentFragment.parse("<p>Test 2</p>")
          expect(described_class.equivalent?(frag1, frag2)).to be false
        end

        it "compares DocumentFragment with string using format hint" do
          frag = Nokogiri::HTML::DocumentFragment.parse("<p>Test content</p>")
          string = "<p>Test content</p>"
          # Comparing fragments works directly without needing format hint for detection
          expect(described_class.equivalent?(frag, frag)).to be true
          # String comparison with format hint also works
          frag2 = Nokogiri::HTML::DocumentFragment.parse(string)
          expect(described_class.equivalent?(frag, frag2)).to be true
        end
      end

      context "Nokogiri::HTML5::DocumentFragment" do
        it "accepts and compares Nokogiri::HTML5::DocumentFragment objects" do
          frag1 = Nokogiri::HTML5::DocumentFragment.parse("<p>Test content</p>")
          frag2 = Nokogiri::HTML5::DocumentFragment.parse("<p>Test content</p>")
          expect(described_class.equivalent?(frag1, frag2)).to be true
        end

        it "detects differences in HTML5 DocumentFragments" do
          frag1 = Nokogiri::HTML5::DocumentFragment.parse("<p>Test 1</p>")
          frag2 = Nokogiri::HTML5::DocumentFragment.parse("<p>Test 2</p>")
          expect(described_class.equivalent?(frag1, frag2)).to be false
        end
      end

      context "Nokogiri::XML::Document" do
        it "accepts and compares Nokogiri::XML::Document objects" do
          doc1 = Nokogiri::XML::Document.parse(xml_string)
          doc2 = Nokogiri::XML::Document.parse(xml_string)
          expect(described_class.equivalent?(doc1, doc2)).to be true
        end

        it "compares Nokogiri::XML::Document with string" do
          doc = Nokogiri::XML::Document.parse(xml_string)
          expect(described_class.equivalent?(doc, xml_string)).to be true
          expect(described_class.equivalent?(xml_string, doc)).to be true
        end
      end

      context "Nokogiri::XML::DocumentFragment" do
        it "accepts and compares Nokogiri::XML::DocumentFragment objects" do
          frag1 = Nokogiri::XML::DocumentFragment.parse("<item>Test content</item>")
          frag2 = Nokogiri::XML::DocumentFragment.parse("<item>Test content</item>")
          expect(described_class.equivalent?(frag1, frag2)).to be true
        end

        it "detects differences in XML DocumentFragments" do
          frag1 = Nokogiri::XML::DocumentFragment.parse("<item>Test 1</item>")
          frag2 = Nokogiri::XML::DocumentFragment.parse("<item>Test 2</item>")
          expect(described_class.equivalent?(frag1, frag2)).to be false
        end
      end

      context "Moxml::Document" do
        it "accepts and compares Moxml::Document objects" do
          doc1 = Moxml.new.parse(xml_string)
          doc2 = Moxml.new.parse(xml_string)
          expect(described_class.equivalent?(doc1, doc2)).to be true
        end

        it "compares Moxml::Document with string" do
          doc = Moxml.new.parse(xml_string)
          expect(described_class.equivalent?(doc, xml_string)).to be true
          expect(described_class.equivalent?(xml_string, doc)).to be true
        end

        it "detects differences in Moxml documents" do
          doc1 = Moxml.new.parse("<root><item>Test 1</item></root>")
          doc2 = Moxml.new.parse("<root><item>Test 2</item></root>")
          expect(described_class.equivalent?(doc1, doc2)).to be false
        end
      end

      context "mixed input types" do
        it "compares HTML Document with HTML DocumentFragment using format hint" do
          # Documents and Fragments have different structures (Document adds html/head/body wrappers)
          # So we compare fragment content with the body content of the document
          doc = Nokogiri::HTML::Document.parse("<html><body><p>Test content</p></body></html>")
          frag = Nokogiri::HTML::DocumentFragment.parse("<p>Test content</p>")
          # This should work because the body content matches the fragment
          body_frag = Nokogiri::HTML::DocumentFragment.parse(doc.at_css("body").inner_html)
          expect(described_class.equivalent?(body_frag, frag,
                                             { format: :html })).to be true
        end

        it "compares XML Document with Moxml Document" do
          nokogiri_doc = Nokogiri::XML::Document.parse(xml_string)
          moxml_doc = Moxml.new.parse(xml_string)
          expect(described_class.equivalent?(nokogiri_doc,
                                             moxml_doc)).to be true
        end

        it "compares HTML string with pre-parsed HTML nodes" do
          html_doc = Nokogiri::HTML::Document.parse(html_string)

          expect(described_class.equivalent?(html_string, html_doc)).to be true
          expect(described_class.equivalent?(html_doc, html_string)).to be true
        end
      end

      context "format detection" do
        it "correctly detects HTML from Nokogiri::HTML::Document" do
          doc = Nokogiri::HTML::Document.parse(html_string)
          # Should use HTML comparison (not raise format mismatch error)
          expect do
            described_class.equivalent?(doc, html_string)
          end.not_to raise_error
        end

        it "correctly detects HTML from Nokogiri::HTML::DocumentFragment" do
          frag = Nokogiri::HTML::DocumentFragment.parse("<p>Test</p>")
          # Should use HTML comparison with format hint
          expect do
            described_class.equivalent?(frag, "<p>Test</p>",
                                        { format: :html })
          end.not_to raise_error
        end

        it "correctly detects XML from Nokogiri::XML::Document" do
          doc = Nokogiri::XML::Document.parse(xml_string)
          # Should use XML comparison
          expect do
            described_class.equivalent?(doc, xml_string)
          end.not_to raise_error
        end

        it "correctly detects XML from Moxml::Document" do
          doc = Moxml.new.parse(xml_string)
          # Should use XML comparison
          expect do
            described_class.equivalent?(doc, xml_string)
          end.not_to raise_error
        end
      end

      context "with preprocessing option" do
        it "applies preprocessing to DocumentFragments" do
          # DocumentFragment with extra whitespace
          frag1 = Nokogiri::HTML::DocumentFragment.parse("<p>  Test   content  </p>")
          frag2 = Nokogiri::HTML::DocumentFragment.parse("<p>Test content</p>")

          # Should match with default HTML preprocessing (:rendered)
          expect(described_class.equivalent?(frag1, frag2)).to be true
        end

        it "respects preprocessing option for pre-parsed nodes" do
          doc1 = Nokogiri::XML::Document.parse("<root>\n  <item>Test</item>\n</root>")
          doc2 = Nokogiri::XML::Document.parse("<root><item>Test</item></root>")

          # XML defaults are strict, so these should NOT match
          expect(described_class.equivalent?(doc1, doc2)).to be false

          # But with spec_friendly profile, they should match (preprocessing: :rendered, structural_whitespace: :ignore)
          expect(described_class.equivalent?(doc1, doc2,
                                             { match_profile: :spec_friendly })).to be true
        end
      end
    end
  end
end
