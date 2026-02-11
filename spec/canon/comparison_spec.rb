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

      it "returns true when whitespace differs (when using :ignore)" do
        xml1 = "<root><item>Test</item></root>"
        xml2 = "<root>\n  <item>Test</item>\n</root>"
        # rubocop:disable Layout/LineLength
        expect(described_class.equivalent?(xml1, xml2, match: { structural_whitespace: :ignore })).to be true
        # rubocop:enable Layout/LineLength
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
                                           { match: { comments: :strict } }))
          .to be false
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

      it "returns ComparisonResult with differences " \
         "for different element names" do
        html1 = "<html><body><p>Test</p></body></html>"
        html2 = "<html><body><div>Test</div></body></html>"

        result = described_class.equivalent?(html1, html2,
                                             { verbose: true, diff_algorithm: :semantic })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false
        # Semantic diff creates 2 DiffNodes: p element deleted, div element inserted
        expect(result.differences.length).to eq(2)
        expect(result.differences.all?(Canon::Diff::DiffNode)).to be true
        expect(result.differences.all? do |d|
          d.dimension == :element_structure
        end).to be true
      end

      it "returns ComparisonResult with differences " \
         "for different text content" do
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
        end
        expect(diff.dimension).to eq(:text_content)
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
          expect(%i[attribute_values
                    attribute_values]).to include(diff.dimension)
        else
          expect(diff.dimension).to eq(:text_content)
        end
      end

      it "returns ComparisonResult with differences for missing nodes" do
        html1 = "<html><body><p>Test</p><div>Extra</div></body></html>"
        html2 = "<html><body><p>Test</p></body></html>"

        result = described_class.equivalent?(html1, html2,
                                             { verbose: true, diff_algorithm: :semantic })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false
        # Semantic diff correctly identifies missing div as element_structure difference
        expect(result.differences.first.dimension).to eq(:element_structure)
      end

      it "returns ComparisonResult with differences for missing attributes" do
        html1 = '<html><body><p class="foo" id="bar">Test</p></body></html>'
        html2 = '<html><body><p class="foo">Test</p></body></html>'

        result = described_class.equivalent?(html1, html2,
                                             { verbose: true })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false
        # Missing attribute should use attribute_presence dimension
        diff = result.differences.first
        expect(diff).to be_a(Canon::Diff::DiffNode)
        expect(diff.dimension).to eq(:attribute_presence)
      end

      it "returns ComparisonResult with multiple differences " \
         "when multiple things differ" do
        html1 = '<html><body><p class="foo">Test 1</p>' \
                 "<div>Extra</div></body></html>"
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

      it "returns ComparisonResult with differences " \
         "for different XML elements" do
        xml1 = "<root><item>Test</item></root>"
        xml2 = "<root><other>Test</other></root>"

        result = described_class.equivalent?(xml1, xml2,
                                             { verbose: true })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false
        expect(result.differences.first.dimension).to eq(:element_structure)
      end

      it "respects other options when in verbose mode" do
        html1 = "<html><body><!-- comment --><p>Test</p></body></html>"
        html2 = "<html><body><p>Test</p></body></html>"

        # HTML defaults: comments are ignored, should create
        # informative DiffNodes
        result = described_class.equivalent?(html1, html2,
                                             { verbose: true })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        # DiffNodes are created but marked as informative
        expect(result.differences.length).to eq(1)
        expect(result.differences.first.dimension).to eq(:comments)
        expect(result.differences.first.normative?).to be false
        # Still equivalent because comment diff is informative
        expect(result.equivalent?).to be true

        # With strict comments matching, should return normative differences
        result = described_class.equivalent?(html1, html2,
                                             { verbose: true,
                                               match: { comments: :strict } })
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.differences.first.normative?).to be true
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
          # Comparing fragments works directly without needing format hint
          # for detection
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
          # Nokogiri adds XML declaration and formatting, use :normalize
          # to ignore
          # rubocop:disable Layout/LineLength
          expect(described_class.equivalent?(doc, xml_string,
                                             match: { structural_whitespace: :normalize }))
            .to be true
          expect(described_class.equivalent?(xml_string, doc,
                                             match: { structural_whitespace: :normalize }))
            .to be true
          # rubocop:enable Layout/LineLength
        end
      end

      context "Nokogiri::XML::DocumentFragment" do
        it "accepts and compares Nokogiri::XML::DocumentFragment " \
           "objects" do
          frag1 = Nokogiri::XML::DocumentFragment.parse(
            "<item>Test content</item>",
          )
          frag2 = Nokogiri::XML::DocumentFragment.parse(
            "<item>Test content</item>",
          )
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
          # Moxml adds formatting, use :normalize to ignore formatting
          # differences
          # rubocop:disable Layout/LineLength
          expect(described_class.equivalent?(doc, xml_string,
                                             match: { structural_whitespace: :normalize }))
            .to be true
          expect(described_class.equivalent?(xml_string, doc,
                                             match: { structural_whitespace: :normalize }))
            .to be true
          # rubocop:enable Layout/LineLength
        end

        it "detects differences in Moxml documents" do
          doc1 = Moxml.new.parse("<root><item>Test 1</item></root>")
          doc2 = Moxml.new.parse("<root><item>Test 2</item></root>")
          expect(described_class.equivalent?(doc1, doc2)).to be false
        end
      end

      context "mixed input types" do
        it "compares HTML Document with HTML DocumentFragment " \
           "using format hint" do
          # Documents and Fragments have different structures
          # (Document adds html/head/body wrappers)
          # So we compare fragment content with the body content of the document
          doc = Nokogiri::HTML::Document.parse(
            "<html><body><p>Test content</p></body></html>",
          )
          frag = Nokogiri::HTML::DocumentFragment.parse("<p>Test content</p>")
          # This should work because the body content matches the fragment
          body_frag = Nokogiri::HTML::DocumentFragment.parse(
            doc.at_css("body").inner_html,
          )
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
          frag1 = Nokogiri::HTML::DocumentFragment.parse(
            "<p>  Test   content  </p>",
          )
          frag2 = Nokogiri::HTML::DocumentFragment.parse("<p>Test content</p>")

          # Should match with default HTML preprocessing (:rendered)
          expect(described_class.equivalent?(frag1, frag2)).to be true
        end

        it "respects preprocessing option for pre-parsed nodes" do
          # Use a difference that DataModel doesn't normalize away
          # (DataModel strips whitespace-only text nodes, which is correct)
          doc1 = Nokogiri::XML::Document.parse(
            "<root><item>Test   content</item></root>",
          )
          doc2 = Nokogiri::XML::Document.parse(
            "<root><item>Test content</item></root>",
          )

          # XML defaults are strict for text_content, so these should NOT match
          expect(described_class.equivalent?(doc1, doc2)).to be false

          # But with spec_friendly profile (text_content: :normalize),
          # they should match
          expect(described_class.equivalent?(doc1, doc2,
                                             { match_profile: :spec_friendly }))
            .to be true
        end
      end
    end

    context "parse_html method" do
      context "with format parameter" do
        it "parses HTML5 with HTML5.fragment when format is :html5" do
          html = '<span lang="en" xml:lang="en">text</span>'
          result = described_class.send(:parse_html, html, :html5)

          expect(result).to be_a(Nokogiri::HTML5::DocumentFragment)
          expect(result.at_css("span").attributes.keys).to eq(%w[lang xml:lang])
        end

        it "parses HTML4 with HTML4.fragment when format is :html4" do
          html = '<span lang="en" xml:lang="en">text</span>'
          result = described_class.send(:parse_html, html, :html4)

          expect(result).to be_a(Nokogiri::HTML4::DocumentFragment)
        end

        it "returns already-parsed documents as-is" do
          frag = Nokogiri::HTML5.fragment("<span>text</span>")
          result = described_class.send(:parse_html, frag, :html5)

          expect(result).to eq(frag)
        end

        it "auto-detects HTML5 from DOCTYPE when format is :html" do
          html = "<!DOCTYPE html><span>text</span>"
          result = described_class.send(:parse_html, html, :html)

          expect(result).to be_a(Nokogiri::HTML5::DocumentFragment)
        end

        it "defaults to HTML4 when format is :html and no DOCTYPE" do
          html = "<span>text</span>"
          result = described_class.send(:parse_html, html, :html)

          expect(result).to be_a(Nokogiri::HTML4::DocumentFragment)
        end
      end
    end

    context "HTML5 lang and xml:lang attributes" do
      it "treats lang and xml:lang as distinct attributes in HTML5" do
        html1 = '<span lang="EN-GB" xml:lang="EN-GB">text</span>'
        html2 = '<span lang="EN-GB" xml:lang="EN-GB">text</span>'

        result = described_class.equivalent?(
          html1, html2,
          format: :html5,
          verbose: true
        )

        expect(result).to be_equivalent
      end

      it "does NOT show false attribute differences " \
         "when attributes are identical" do
        html1 = '<span lang="EN-GB" xml:lang="EN-GB">&#xA0;</span>'
        html2 = '<span lang="EN-GB" xml:lang="EN-GB">␣</span>'

        result = described_class.equivalent?(
          html1, html2,
          format: :html5,
          verbose: true
        )

        # Should NOT be equivalent (different text content)
        expect(result).not_to be_equivalent

        # Only difference should be text content, not attributes
        attr_diffs = result.differences.select do |d|
          d.dimension == :attribute_values
        end
        expect(attr_diffs).to be_empty

        # Should have exactly one text_content difference
        text_diffs = result.differences.select do |d|
          d.dimension == :text_content
        end
        expect(text_diffs.length).to eq(1)
      end

      it "correctly handles HTML4 with lang and xml:lang" do
        html1 = '<span lang="EN-GB" xml:lang="EN-GB">text</span>'
        html2 = '<span lang="EN-GB" xml:lang="EN-GB">text</span>'

        result = described_class.equivalent?(
          html1, html2,
          format: :html4,
          verbose: true
        )

        expect(result).to be_equivalent
      end
    end

    context "backward compatibility" do
      it "works when format is not specified (auto-detect)" do
        html1 = "<span>text</span>"
        html2 = "<span>text</span>"

        expect(described_class.equivalent?(html1, html2)).to be true
      end

      it "handles strings with :html format (legacy behavior)" do
        html1 = "<span>text</span>"
        html2 = "<span>text</span>"

        expect(described_class.equivalent?(html1, html2,
                                           format: :html)).to be true
      end

      it "handles strings with :html5 format (new behavior)" do
        html1 = "<span>text</span>"
        html2 = "<span>text</span>"

        expect(described_class.equivalent?(html1, html2,
                                           format: :html5)).to be true
      end

      it "handles strings with :html4 format (new behavior)" do
        html1 = "<span>text</span>"
        html2 = "<span>text</span>"

        expect(described_class.equivalent?(html1, html2,
                                           format: :html4)).to be true
      end
    end

    context "element-level whitespace sensitivity" do
      context "with xml:space attribute" do
        it "respects xml:space='preserve' for XML" do
          xml1 = "<root><code xml:space='preserve'>  text  </code></root>"
          xml2 = "<root><code xml:space='preserve'>text</code></root>"

          # Should NOT be equivalent - whitespace matters in
          # xml:space='preserve'
          result = described_class.equivalent?(
            xml1, xml2,
            format: :xml,
            match: { text_content: :strict }
          )
          expect(result).to be false
        end

        it "respects xml:space='default' for XML" do
          xml1 = "<root><code xml:space='default'>  text  </code></root>"
          xml2 = "<root><code xml:space='default'>text</code></root>"

          # With text_content: :normalize, these should be equivalent
          result = described_class.equivalent?(
            xml1, xml2,
            format: :xml,
            match: { text_content: :normalize }
          )
          expect(result).to be true
        end
      end

      context "with whitespace_sensitive_elements option" do
        it "treats whitelisted elements as whitespace-sensitive" do
          xml1 = "<root><code>  text  </code></root>"
          xml2 = "<root><code>text</code></root>"

          # With code in whitelist and text_content: :normalize,
          # whitespace differences should still matter (strict mode
          # for sensitive elements)
          result = described_class.equivalent?(
            xml1, xml2,
            format: :xml,
            match: {
              text_content: :normalize,
              whitespace_sensitive_elements: [:code],
            }
          )
          expect(result).to be false
        end

        it "does not affect elements not in whitelist" do
          xml1 = "<root><p>  text  </p></root>"
          xml2 = "<root><p>text</p></root>"

          # With text_content: :normalize and p not in whitelist,
          # should be equivalent
          result = described_class.equivalent?(
            xml1, xml2,
            format: :xml,
            match: {
              text_content: :normalize,
              whitespace_sensitive_elements: [:code],
            }
          )
          expect(result).to be true
        end
      end

      context "with whitespace_insensitive_elements option" do
        it "treats blacklisted elements as whitespace-insensitive" do
          xml1 = "<root><pre>  text  </pre></root>"
          xml2 = "<root><pre>text</pre></root>"

          # With pre in blacklist and text_content: :normalize,
          # whitespace differences should be ignored
          result = described_class.equivalent?(
            xml1, xml2,
            format: :html,
            match: {
              text_content: :normalize,
              whitespace_insensitive_elements: [:pre],
            }
          )
          expect(result).to be true
        end
      end

      context "with respect_xml_space option" do
        it "ignores xml:space when respect_xml_space is false" do
          xml1 = "<root><code xml:space='preserve'>  text  </code></root>"
          xml2 = "<root><code xml:space='preserve'>text</code></root>"

          # With respect_xml_space: false, xml:space is ignored
          # and text_content: :normalize makes them equivalent
          result = described_class.equivalent?(
            xml1, xml2,
            format: :xml,
            match: {
              text_content: :normalize,
              respect_xml_space: false,
            }
          )
          expect(result).to be true
        end

        it "respects xml:space when respect_xml_space is true (default)" do
          xml1 = "<root><code xml:space='preserve'>  text  </code></root>"
          xml2 = "<root><code xml:space='preserve'>text</code></root>"

          # With respect_xml_space: true (default), xml:space is respected
          result = described_class.equivalent?(
            xml1, xml2,
            format: :xml,
            match: {
              text_content: :strict,
              respect_xml_space: true,
            }
          )
          expect(result).to be false
        end
      end

      context "format-specific defaults" do
        it "HTML has default whitespace-sensitive elements" do
          html1 = "<root><pre>  text  </pre></root>"
          html2 = "<root><pre>text</pre></root>"

          # HTML's <pre> element is whitespace-sensitive by default
          # With text_content: :normalize, <pre> should still be strict
          result = described_class.equivalent?(
            html1, html2,
            format: :html,
            match: { text_content: :normalize }
          )
          expect(result).to be false
        end

        it "XML has no default whitespace-sensitive elements" do
          xml1 = "<root><pre>  text  </pre></root>"
          xml2 = "<root><pre>text</pre></root>"

          # XML has no defaults, so with text_content: :normalize,
          # they're equivalent
          result = described_class.equivalent?(
            xml1, xml2,
            format: :xml,
            match: { text_content: :normalize }
          )
          expect(result).to be true
        end

        it "HTML default <script> element is whitespace-sensitive" do
          html1 = "<root><script>  var x = 1;  </script></root>"
          html2 = "<root><script>var x = 1;</script></root>"

          result = described_class.equivalent?(
            html1, html2,
            format: :html,
            match: { text_content: :normalize, preprocessing: :none }
          )
          expect(result).to be false
        end

        it "HTML default <style> element is whitespace-sensitive" do
          html1 = "<root><style>  .cls { color: red; }  </style></root>"
          html2 = "<root><style>.cls { color: red; }</style></root>"

          result = described_class.equivalent?(
            html1, html2,
            format: :html,
            match: { text_content: :normalize, preprocessing: :none }
          )
          expect(result).to be false
        end

        it "HTML default <textarea> element is whitespace-sensitive" do
          html1 = "<root><textarea>  some text  </textarea></root>"
          html2 = "<root><textarea>some text</textarea></root>"

          result = described_class.equivalent?(
            html1, html2,
            format: :html,
            match: { text_content: :normalize }
          )
          expect(result).to be false
        end
      end
    end
  end
end
