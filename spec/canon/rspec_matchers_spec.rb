# frozen_string_literal: true

require "spec_helper"
require "canon/rspec_matchers"

RSpec.describe Canon::RSpecMatchers do
  # Test data - minimal examples for each format
  let(:xml_original) { '<root><a b="2" c="1">text</a></root>' }
  let(:xml_reordered) { '<root><a c="1" b="2">text</a></root>' }
  let(:xml_different) { "<root><d>other</d></root>" }

  let(:yaml_original) { "---\nz: 3\na: 1\nb: 2\n" }
  let(:yaml_reordered) { "---\na: 1\nb: 2\nz: 3\n" }
  let(:yaml_different) { "---\nc: 4\n" }

  let(:json_original) { '{"z":3,"a":1,"b":2}' }
  let(:json_reordered) { '{"a":1,"b":2,"z":3}' }
  let(:json_different) { '{"c":4}' }

  describe "#be_serialization_equivalent_to" do
    it "matches equivalent XML with format parameter" do
      expect(xml_original).to be_serialization_equivalent_to(xml_reordered,
                                                             format: :xml)
    end

    it "matches equivalent YAML with format parameter" do
      expect(yaml_original).to be_serialization_equivalent_to(yaml_reordered,
                                                              format: :yaml)
    end

    it "matches equivalent JSON with format parameter" do
      expect(json_original).to be_serialization_equivalent_to(json_reordered,
                                                              format: :json)
    end

    it "raises error for unsupported format" do
      expect do
        expect(xml_original).to be_serialization_equivalent_to(xml_reordered,
                                                               format: :unsupported)
      end.to raise_error(Canon::Error, "Unsupported format: unsupported")
    end
  end

  describe "#be_xml_equivalent_to" do
    it "matches equivalent XML documents" do
      expect(xml_original).to be_xml_equivalent_to(xml_reordered)
    end

    it "does not match different XML documents" do
      expect(xml_original).not_to be_xml_equivalent_to(xml_different)
    end

    context "with complex XML structures" do
      let(:xml1) do
        <<~XML
          <root>
            <element id="1" name="first">
              <child>content</child>
            </element>
          </root>
        XML
      end

      let(:xml2) do
        <<~XML
          <root>
            <element name="first" id="1">
              <child>content</child>
            </element>
          </root>
        XML
      end

      let(:xml3) do
        <<~XML
          <root>
            <element id="1" name="different">
              <child>content</child>
            </element>
          </root>
        XML
      end

      it "matches XML with reordered attributes" do
        expect(xml1).to be_xml_equivalent_to(xml2)
      end

      it "does not match XML with different attribute values" do
        expect(xml1).not_to be_xml_equivalent_to(xml3)
      end
    end

    context "with comments" do
      let(:xml1) { "<root><!-- comment 1 --><a>text</a></root>" }
      let(:xml2) { "<root><!-- comment 2 --><a>text</a></root>" }

      it "matches XML with different comments (comments ignored by default)" do
        expect(xml1).to be_xml_equivalent_to(xml2, match: { comments: :ignore })
      end
    end

    context "with nested structures" do
      let(:xml1) do
        <<~XML
          <root>
            <level1>
              <level2>
                <level3>deep content</level3>
              </level2>
            </level1>
          </root>
        XML
      end

      let(:xml2) do
        <<~XML
          <root>
            <level1>
              <level2>
                <level3>deep content</level3>
              </level2>
            </level1>
          </root>
        XML
      end

      it "matches deeply nested equivalent XML" do
        expect(xml1).to be_xml_equivalent_to(xml2)
      end
    end
  end

  describe "#be_analogous_with" do
    it "matches equivalent XML documents (legacy matcher)" do
      expect(xml_original).to be_analogous_with(xml_reordered)
    end
  end

  describe "#be_yaml_equivalent_to" do
    it "matches equivalent YAML documents" do
      expect(yaml_original).to be_yaml_equivalent_to(yaml_reordered)
    end

    it "does not match different YAML documents" do
      expect(yaml_original).not_to be_yaml_equivalent_to(yaml_different)
    end

    context "with nested structures" do
      let(:yaml1) do
        <<~YAML
          database:
            host: localhost
            port: 5432
          settings:
            debug: true
        YAML
      end

      let(:yaml2) do
        <<~YAML
          settings:
            debug: true
          database:
            port: 5432
            host: localhost
        YAML
      end

      it "matches YAML with reordered keys at all levels" do
        expect(yaml1).to be_yaml_equivalent_to(yaml2)
      end
    end
  end

  describe "#be_json_equivalent_to" do
    it "matches equivalent JSON documents" do
      expect(json_original).to be_json_equivalent_to(json_reordered)
    end

    it "does not match different JSON documents" do
      expect(json_original).not_to be_json_equivalent_to(json_different)
    end

    context "with nested structures" do
      let(:json1) { '{"a":{"b":{"c":1}},"d":2}' }
      let(:json2) { '{"d":2,"a":{"b":{"c":1}}}' }

      it "matches JSON with reordered keys at all levels" do
        expect(json1).to be_json_equivalent_to(json2)
      end
    end
  end

  describe "#be_html_equivalent_to" do
    let(:html1) { "<div><p>Hello</p></div>" }
    let(:html2) { "<div>  <p>  Hello  </p>  </div>" }
    let(:html3) { "<div><p>Goodbye</p></div>" }

    it "matches equivalent HTML documents" do
      expect(html1).to be_html_equivalent_to(html2)
    end

    it "does not match different HTML documents" do
      expect(html1).not_to be_html_equivalent_to(html3)
    end

    context "with complex HTML structures" do
      let(:html1) do
        <<~HTML
          <html>
            <head><title>Test</title></head>
            <body>
              <div class="container" id="main">
                <p>Content</p>
              </div>
            </body>
          </html>
        HTML
      end

      let(:html2) do
        <<~HTML
          <html>
            <head><title>Test</title></head>
            <body>
              <div id="main" class="container">
                <p>Content</p>
              </div>
            </body>
          </html>
        HTML
      end

      it "matches HTML with reordered attributes" do
        expect(html1).to be_html_equivalent_to(html2)
      end
    end
  end

  describe "#be_html4_equivalent_to" do
    let(:html1) { "<div><p>Content</p></div>" }
    let(:html2) { "<div>  <p>  Content  </p>  </div>" }

    it "matches equivalent HTML4 documents" do
      expect(html1).to be_html4_equivalent_to(html2)
    end
  end

  describe "#be_html5_equivalent_to" do
    let(:html1) { "<div><p>Content</p></div>" }
    let(:html2) { "<div>  <p>  Content  </p>  </div>" }

    it "matches equivalent HTML5 documents" do
      expect(html1).to be_html5_equivalent_to(html2)
    end
  end

  describe "chain methods" do
    it "supports with_profile chain method" do
      xml1 = "<root><item>test</item></root>"
      xml2 = "<root><item>test</item></root>"
      expect(xml1).to be_xml_equivalent_to(xml2).with_profile(:strict)
    end

    it "supports with_options chain method" do
      xml1 = "<root a=\"1\" b=\"2\"/>"
      xml2 = "<root b=\"2\" a=\"1\"/>"
      expect(xml1).to be_xml_equivalent_to(xml2).with_options(attribute_order: :ignore)
    end

    it "supports with_match chain method" do
      xml1 = "<root><item>test</item></root>"
      xml2 = "<root><item>test</item></root>"
      expect(xml1).to be_xml_equivalent_to(xml2).with_match(text_content: :normalize)
    end

    it "supports chained with_profile and with_options" do
      xml1 = "<root a=\"1\" b=\"2\"><item>test</item></root>"
      xml2 = "<root b=\"2\" a=\"1\"><item>test</item></root>"
      expect(xml1).to be_xml_equivalent_to(xml2)
        .with_profile(:spec_friendly)
        .with_options(attribute_order: :ignore)
    end

    it "supports show_diffs chain method with :all" do
      matcher = be_xml_equivalent_to("<root/>").show_diffs(:all)
      expect(matcher).to be_a(Canon::RSpecMatchers::SerializationMatcher)
    end

    it "supports show_diffs chain method with :normative" do
      matcher = be_xml_equivalent_to("<root/>").show_diffs(:normative)
      expect(matcher).to be_a(Canon::RSpecMatchers::SerializationMatcher)
    end

    it "supports show_diffs chain method with :informative" do
      matcher = be_xml_equivalent_to("<root/>").show_diffs(:informative)
      expect(matcher).to be_a(Canon::RSpecMatchers::SerializationMatcher)
    end
  end

  describe "failure messages" do
    context "when XML documents differ" do
      let(:xml1) { "<root><a>1</a></root>" }
      let(:xml2) { "<root><a>2</a></root>" }

      it "provides a helpful failure message" do
        expect do
          expect(xml1).to be_xml_equivalent_to(xml2)
        end.to raise_error(RSpec::Expectations::ExpectationNotMetError,
                           /expected XML to be equivalent/)
      end
    end

    context "when HTML documents differ" do
      let(:html1) { "<div>Hello</div>" }
      let(:html2) { "<div>Goodbye</div>" }

      it "provides a helpful failure message" do
        expect do
          expect(html1).to be_html_equivalent_to(html2)
        end.to raise_error(RSpec::Expectations::ExpectationNotMetError,
                           /expected HTML to be equivalent/)
      end
    end
  end

  describe "RSpec integration" do
    it "includes matchers in RSpec context" do
      expect(self).to respond_to(:be_serialization_equivalent_to)
      expect(self).to respond_to(:be_xml_equivalent_to)
      expect(self).to respond_to(:be_analogous_with)
      expect(self).to respond_to(:be_yaml_equivalent_to)
      expect(self).to respond_to(:be_json_equivalent_to)
      expect(self).to respond_to(:be_html_equivalent_to)
      expect(self).to respond_to(:be_html4_equivalent_to)
      expect(self).to respond_to(:be_html5_equivalent_to)
    end
  end

  describe "edge cases" do
    context "with empty documents" do
      it "matches empty XML documents" do
        expect("<root/>").to be_xml_equivalent_to("<root></root>")
      end

      it "matches empty JSON objects" do
        expect("{}").to be_json_equivalent_to("{}")
      end

      it "matches empty YAML documents" do
        expect("---\n").to be_yaml_equivalent_to("---\n")
      end
    end

    context "with special characters" do
      let(:xml1) { "<root><a>&lt;&gt;&amp;</a></root>" }
      let(:xml2) { "<root><a>&lt;&gt;&amp;</a></root>" }

      it "matches XML with escaped special characters" do
        expect(xml1).to be_xml_equivalent_to(xml2)
      end
    end

    context "with numeric values" do
      let(:json1) { '{"a":1,"b":2.5,"c":true}' }
      let(:json2) { '{"c":true,"b":2.5,"a":1}' }

      it "matches JSON with different numeric types" do
        expect(json1).to be_json_equivalent_to(json2)
      end
    end
  end

  describe "configuration" do
    before do
      # Save original configuration
      @original_xml_mode = Canon::Config.instance.xml.diff.mode
      @original_xml_color = Canon::Config.instance.xml.diff.use_color

      # Stub color detection to return true (as if in a TTY)
      allow(Canon::ColorDetector).to receive(:supports_color?).and_return(true)
    end

    after do
      # Restore original configuration
      Canon::Config.configure do |config|
        config.xml.diff.mode = @original_xml_mode
        config.xml.diff.use_color = @original_xml_color
      end
    end

    it "allows configuration via configure block" do
      Canon::Config.configure do |config|
        config.xml.diff.mode = :by_object
        config.xml.diff.use_color = false
      end

      expect(Canon::Config.instance.xml.diff.mode).to eq(:by_object)
      expect(Canon::Config.instance.xml.diff.use_color).to be(false)
    end

    it "has default configuration" do
      Canon::Config.reset!

      expect(Canon::Config.instance.xml.diff.mode).to eq(:by_line)
      expect(Canon::Config.instance.xml.diff.use_color).to be(true)
    end

    it "can be configured for by_object diff mode" do
      Canon::Config.configure do |config|
        config.xml.diff.mode = :by_object
      end

      expect(Canon::Config.instance.xml.diff.mode).to eq(:by_object)
    end

    it "can be configured to disable colors" do
      Canon::Config.configure do |config|
        config.xml.diff.use_color = false
      end

      expect(Canon::Config.instance.xml.diff.use_color).to be(false)
    end
  end

  describe "visual diff generation" do
    before do
      # Ensure default config for these tests
      described_class.reset_config
    end

    context "with XML differences" do
      let(:xml1) { '<root><element attr1="value1">text</element></root>' }
      let(:xml2) { '<root><element attr1="value2">text</element></root>' }

      it "generates visual diff in failure message" do
        expect(xml1).to be_xml_equivalent_to(xml2)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        # Verify that diff is included in the failure message
        expect(e.message).to match(/Line-by-line diff/)
        expect(e.message).to include("attr1")
      end

      it "shows line numbers in diff" do
        expect(xml1).to be_xml_equivalent_to(xml2)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        # Should have line numbers like "  3|    - |" or "   |   3+ |"
        # Note: ANSI color codes may be present, so use flexible regex
        expect(e.message).to match(/\d+.*\|/)
      end
    end

    context "with missing attributes in XML" do
      let(:xml1) { '<root><element id="A">text</element></root>' }
      let(:xml2) { '<root><element id="A" extra="value">text</element></root>' }

      it "highlights missing attributes in diff" do
        expect(xml1).to be_xml_equivalent_to(xml2)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to match(/Line-by-line diff/)
        # Should show the attribute difference
        expect(e.message).to include("extra")
      end
    end

    context "with JSON differences" do
      let(:json1) { '{"name":"Alice","age":30}' }
      let(:json2) { '{"name":"Bob","age":30}' }

      it "generates visual diff for JSON" do
        expect(json1).to be_json_equivalent_to(json2)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to match(/Line-by-line diff/)
        expect(e.message).to include("Alice")
        expect(e.message).to include("Bob")
      end
    end

    context "with YAML differences" do
      let(:yaml1) { "name: Alice\nage: 30\n" }
      let(:yaml2) { "name: Bob\nage: 30\n" }

      it "generates visual diff for YAML" do
        expect(yaml1).to be_yaml_equivalent_to(yaml2)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to match(/Line-by-line diff/)
        expect(e.message).to include("Alice")
        expect(e.message).to include("Bob")
      end
    end

    context "with HTML differences" do
      let(:html1) { "<div><p>Hello</p></div>" }
      let(:html2) { "<div><p>Goodbye</p></div>" }

      it "generates visual diff for HTML" do
        expect(html1).to be_html_equivalent_to(html2)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to match(/Line-by-line diff/)
      end
    end

    context "when configured for by_object mode" do
      before do
        Canon::Config.configure do |config|
          config.json.diff.mode = :by_object
        end
      end

      after do
        Canon::Config.reset!
      end

      it "generates by-object diff" do
        json1 = '{"name":"Alice","age":30}'
        json2 = '{"name":"Bob","age":25}'

        begin
          expect(json1).to be_json_equivalent_to(json2)
        rescue RSpec::Expectations::ExpectationNotMetError => e
          # by_object mode should show Visual Diff:
          expect(e.message).to include("Visual Diff:")
        end
      end
    end
  end

  describe "matcher protocol compliance" do
    let(:xml1) { "<root><a>1</a></root>" }
    let(:xml2) { "<root><a>2</a></root>" }
    let(:matcher) { be_xml_equivalent_to(xml2) }

    before do
      matcher.matches?(xml1)
    end

    it "provides expected value" do
      expect(matcher.expected).to be_a(String)
    end

    it "provides actual value" do
      expect(matcher.actual).to be_a(String)
    end

    it "is not diffable (uses custom diff)" do
      expect(matcher.diffable).to be(false)
    end

    it "provides failure message" do
      expect(matcher.failure_message).to include("expected XML to be equivalent")
    end

    it "provides negated failure message" do
      expect(matcher.failure_message_when_negated).to include("not to be equivalent")
    end
  end

  describe "whitespace normalization configuration" do
    before do
      # Save original configuration
      @original_profile = described_class.xml.match.profile
      @original_options = described_class.xml.match.options.dup
    end

    after do
      # Restore original configuration
      described_class.configure do |config|
        config.xml.match.profile = @original_profile
        config.xml.match.options = @original_options
      end
    end

    it "can be enabled via configuration" do
      described_class.configure do |config|
        config.xml.match.options = { text_content: :normalize }
      end

      expect(described_class.xml.match.options[:text_content]).to eq(:normalize)
    end

    it "can be disabled via configuration" do
      described_class.configure do |config|
        config.xml.match.options = { text_content: :strict }
      end

      expect(described_class.xml.match.options[:text_content]).to eq(:strict)
    end

    it "is disabled by default" do
      described_class.reset_config

      # Default for XML is strict (no options means strict behavior)
      expect(described_class.xml.match.options[:text_content]).to be_nil
    end

    context "when enabled" do
      before do
        described_class.configure do |config|
          config.xml.match.options = {
            text_content: :normalize,
            structural_whitespace: :normalize,
          }
        end
      end

      context "with tag boundary whitespace" do
        let(:xml1) { "<root><element>text</element></root>" }
        let(:xml2) { "<root>\n  <element>\n    text\n  </element>\n</root>" }
        let(:xml3) { "<root>  <element>  text  </element>  </root>" }

        it "matches XML with different tag boundary whitespace" do
          expect(xml1).to be_xml_equivalent_to(xml2)
          expect(xml1).to be_xml_equivalent_to(xml3)
          expect(xml2).to be_xml_equivalent_to(xml3)
        end
      end

      context "with multiple whitespace characters" do
        let(:xml1) { "<root><a>single space</a></root>" }
        let(:xml2) { "<root><a>single  space</a></root>" }
        let(:xml3) { "<root><a>single   space</a></root>" }
        let(:xml4) { "<root><a>single\t\nspace</a></root>" }

        it "normalizes multiple spaces to single space" do
          expect(xml1).to be_xml_equivalent_to(xml2)
          expect(xml1).to be_xml_equivalent_to(xml3)
          expect(xml1).to be_xml_equivalent_to(xml4)
        end
      end

      context "with leading and trailing whitespace" do
        let(:xml1) { "<root><a>text</a></root>" }
        let(:xml2) { "<root><a>  text  </a></root>" }
        let(:xml3) { "<root><a>\n  text\n  </a></root>" }

        it "strips leading and trailing whitespace from text nodes" do
          expect(xml1).to be_xml_equivalent_to(xml2)
          expect(xml1).to be_xml_equivalent_to(xml3)
        end
      end

      context "with pretty-printed XML" do
        let(:xml1) do
          "<root><person><name>John</name><age>30</age></person></root>"
        end

        let(:xml2) do
          <<~XML
            <root>
              <person>
                <name>John</name>
                <age>30</age>
              </person>
            </root>
          XML
        end

        let(:xml3) do
          <<~XML
            <root>
            <person>
            <name>John</name>
            <age>30</age>
            </person>
            </root>
          XML
        end

        it "matches compact and pretty-printed XML" do
          expect(xml1).to be_xml_equivalent_to(xml2)
          expect(xml1).to be_xml_equivalent_to(xml3)
          expect(xml2).to be_xml_equivalent_to(xml3)
        end
      end

      context "with mixed content" do
        let(:xml1) { "<p>This is <em>important</em> text.</p>" }
        let(:xml2) { "<p>This is <em>important</em>  text.</p>" }
        let(:xml3) { "<p>This is  <em>important</em> text.</p>" }

        it "normalizes whitespace in mixed content" do
          expect(xml1).to be_xml_equivalent_to(xml2)
          expect(xml1).to be_xml_equivalent_to(xml3)
        end
      end

      context "with nested elements and whitespace" do
        let(:xml1) do
          "<root><outer><inner><deep>content</deep></inner></outer></root>"
        end

        let(:xml2) do
          <<~XML
            <root>
              <outer>
                <inner>
                  <deep>content</deep>
                </inner>
              </outer>
            </root>
          XML
        end

        it "normalizes whitespace at all nesting levels" do
          expect(xml1).to be_xml_equivalent_to(xml2)
        end
      end

      context "with actual content differences" do
        let(:xml1) { "<root><a>text one</a></root>" }
        let(:xml2) { "<root><a>text two</a></root>" }

        it "still detects actual content differences" do
          expect(xml1).not_to be_xml_equivalent_to(xml2)
        end
      end

      context "with empty elements" do
        let(:xml1) { "<root><empty/></root>" }
        let(:xml2) { "<root>  <empty/>  </root>" }
        let(:xml3) { "<root>\n  <empty/>\n</root>" }

        it "matches empty elements with surrounding whitespace" do
          expect(xml1).to be_xml_equivalent_to(xml2)
          expect(xml1).to be_xml_equivalent_to(xml3)
        end
      end

      context "with attributes" do
        let(:xml1) { '<root><element attr="value">text</element></root>' }
        let(:xml2) do
          <<~XML
            <root>
              <element attr="value">
                text
              </element>
            </root>
          XML
        end

        it "normalizes whitespace while preserving attribute values" do
          expect(xml1).to be_xml_equivalent_to(xml2)
        end

        it "does not normalize whitespace within attribute values" do
          xml_attr1 = '<root attr="value  with  spaces"/>'
          xml_attr2 = '<root attr="value with spaces"/>'

          expect(xml_attr1).not_to be_xml_equivalent_to(xml_attr2)
        end
      end

      context "with real-world isodoc example" do
        # Based on the actual failing test case from isodoc
        let(:xml1) do
          <<~XML
            <iso-standard>
              <bibdata>
                <contributor>
                  <person>
                    <affiliation>
                      <organization>
                        <address>
                          <formattedAddress>Address Line 1</formattedAddress>
                        </address>
                      </organization>
                    </affiliation>
                  </person>
                </contributor>
              </bibdata>
            </iso-standard>
          XML
        end

        let(:xml2) do
          "<iso-standard><bibdata><contributor><person>" \
            "<affiliation><organization><address>" \
            "<formattedAddress>Address Line 1</formattedAddress>" \
            "</address></organization></affiliation></person>" \
            "</contributor></bibdata></iso-standard>"
        end

        it "matches pretty-printed and compact isodoc XML" do
          expect(xml1).to be_xml_equivalent_to(xml2)
        end
      end

      context "with comments" do
        let(:xml1) { "<root><!-- comment --><a>text</a></root>" }
        let(:xml2) do
          <<~XML
            <root>
              <!-- comment -->
              <a>text</a>
            </root>
          XML
        end

        it "normalizes whitespace around comments" do
          expect(xml1).to be_xml_equivalent_to(xml2)
        end
      end
    end

    context "when disabled (default behavior)" do
      before do
        described_class.configure do |config|
          config.xml.match.options = {
            text_content: :strict,
            structural_whitespace: :strict,
          }
        end
      end

      it "uses C14N canonicalization for comparison" do
        # C14N preserves significant whitespace but normalizes attributes
        xml1 = '<root><a attr="value">text</a></root>'
        xml2 = '<root><a attr="value">text</a></root>'

        expect(xml1).to be_xml_equivalent_to(xml2)
      end

      it "does not match when whitespace differs without normalization enabled" do
        # Without normalize_tag_whitespace, whitespace between tags is preserved
        xml1 = "<root><a>text</a></root>"
        xml2 = "<root>\n  <a>\n    text\n  </a>\n</root>"

        # These should NOT match because whitespace is preserved in C14N
        expect(xml1).not_to be_xml_equivalent_to(xml2)
      end
    end

    context "interaction with text_content normalization" do
      before do
        described_class.configure do |config|
          config.xml.match.options = {
            text_content: :normalize,
            structural_whitespace: :normalize,
          }
        end
      end

      it "normalizes whitespace when text_content normalization is enabled" do
        xml1 = "<root><a>text</a></root>"
        xml2 = "<root>  <a>  text  </a>  </root>"

        expect(xml1).to be_xml_equivalent_to(xml2)
      end
    end
  end

  describe "regression prevention" do
    # These tests ensure the visual diff behavior doesn't regress

    context "with deeply nested element changes" do
      # Regression test for: showing all parent elements instead of just the deepest changed element
      let(:xml1) do
        <<~XML
          <iso-standard>
            <bibdata>
              <contributor>
                <person>
                  <affiliation>
                    <organization>
                      <address>
                        <formattedAddress>Address Line 1</formattedAddress>
                      </address>
                    </organization>
                  </affiliation>
                </person>
              </contributor>
            </bibdata>
          </iso-standard>
        XML
      end

      let(:xml2) do
        <<~XML
          <iso-standard>
            <bibdata>
              <contributor>
                <person>
                  <affiliation>
                    <organization>
                      <address>
                        <formattedAddress>Address Line 2</formattedAddress>
                      </address>
                    </organization>
                  </affiliation>
                </person>
              </contributor>
            </bibdata>
          </iso-standard>
        XML
      end

      it "only shows the deepest changed element, not all ancestors" do
        expect(xml1).to be_xml_equivalent_to(xml2)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        # Should show only the formattedAddress element that changed
        expect(e.message).to include("formattedAddress")

        # Should NOT show all the parent elements in the element path
        # Only the immediate context should be shown
        lines = e.message.lines
        element_lines = lines.select { |l| l.include?("Element:") }

        # Should have a reasonable number of element sections (not dozens showing every parent)
        expect(element_lines.size).to be < 5
      end

      it "shows precise element path for the changed element" do
        expect(xml1).to be_xml_equivalent_to(xml2)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        # Should show the changed element in the diff output
        # New format uses line-by-line diff instead of "Element:" headers
        expect(e.message).to include("formattedAddress")
        expect(e.message).to match(/Line-by-line diff/)
      end
    end

    context "with multiple changes at different depths" do
      let(:xml1) do
        <<~XML
          <root>
            <level1 attr="old">
              <level2>
                <level3>old content</level3>
              </level2>
            </level1>
            <sibling>unchanged</sibling>
          </root>
        XML
      end

      let(:xml2) do
        <<~XML
          <root>
            <level1 attr="new">
              <level2>
                <level3>new content</level3>
              </level2>
            </level1>
            <sibling>unchanged</sibling>
          </root>
        XML
      end

      it "shows each changed element separately" do
        expect(xml1).to be_xml_equivalent_to(xml2)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        # Should show the content change
        expect(e.message).to include("content")

        # Should show the line-by-line diff format
        expect(e.message).to match(/Line-by-line diff/)

        # Should show both the attribute and content changes
        expect(e.message).to include("attr")
        expect(e.message).to include("level")
      end
    end

    context "with sibling elements having changes" do
      let(:xml1) do
        <<~XML
          <root>
            <item id="1">original</item>
            <item id="2">original</item>
            <item id="3">original</item>
          </root>
        XML
      end

      let(:xml2) do
        <<~XML
          <root>
            <item id="1">original</item>
            <item id="2">changed</item>
            <item id="3">original</item>
          </root>
        XML
      end

      it "shows only the changed sibling element" do
        expect(xml1).to be_xml_equivalent_to(xml2)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        # Should show the middle item that changed
        expect(e.message).to include("item")
        expect(e.message).to include("changed")

        # Should show context lines around the change
        # With default context_lines setting, we expect to see some "original" text
        # but not all unchanged items
        unchanged_count = e.message.scan(/original/).size
        # In the new format with context lines, we see the changed line plus context
        # Accept up to 4 occurrences (context before, context after, and grouping)
        expect(unchanged_count).to be <= 4
      end
    end

    context "with formatted address structure (real-world regression)" do
      let(:xml1) do
        <<~XML
          <iso-standard>
            <bibdata>
              <contributor>
                <person>
                  <affiliation>
                    <organization>
                      <address>
                        <formattedAddress>Line 1, City A, Country A</formattedAddress>
                      </address>
                    </organization>
                  </affiliation>
                </person>
              </contributor>
            </bibdata>
          </iso-standard>
        XML
      end

      let(:xml2) do
        <<~XML
          <iso-standard>
            <bibdata>
              <contributor>
                <person>
                  <affiliation>
                    <organization>
                      <address>
                        <formattedAddress>Line 1, City B, Country B</formattedAddress>
                      </address>
                    </organization>
                  </affiliation>
                </person>
              </contributor>
            </bibdata>
          </iso-standard>
        XML
      end

      it "shows only the deepest changed element, not the entire document hierarchy" do
        expect(xml1).to be_xml_equivalent_to(xml2)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        diff_message = e.message

        # Should show formattedAddress in the element path
        expect(diff_message).to match(/formattedAddress/)

        # Should NOT have multiple Element: sections for every ancestor
        # (iso-standard, bibdata, contributor, person, affiliation, organization, address)
        element_sections = diff_message.scan(/^Element:/).size

        # Should have a small number of element sections (only for actual changes)
        # not 7+ sections for every level of nesting
        expect(element_sections).to be < 5

        # Verify the diff shows the actual change
        expect(diff_message).to include("City")
      end
    end

    context "with by_object diff mode" do
      before do
        Canon::Config.configure do |config|
          config.xml.diff.mode = :by_object
        end
      end

      after do
        Canon::Config.reset!
      end

      let(:xml1) do
        <<~XML
          <root>
            <deep>
              <nested>
                <element attr="old">content</element>
              </nested>
            </deep>
          </root>
        XML
      end

      let(:xml2) do
        <<~XML
          <root>
            <deep>
              <nested>
                <element attr="new">content</element>
              </nested>
            </deep>
          </root>
        XML
      end

      it "shows only the changed element in by_object mode" do
        expect(xml1).to be_xml_equivalent_to(xml2)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        # Should show Visual Diff: (tree-style format)
        expect(e.message).to include("Visual Diff:")

        # Should show the element in the tree
        expect(e.message).to include("element")

        # Should show a tree structure (with box drawing characters)
        expect(e.message).to match(/└──|├──/)
      end
    end

    context "with C14N canonicalization" do
      let(:xml1) do
        <<~XML
          <root xmlns="http://example.com">
            <element attr="value">text</element>
          </root>
        XML
      end

      let(:xml2) do
        <<~XML
          <root xmlns="http://example.com">
            <element attr="different">text</element>
          </root>
        XML
      end

      it "shows diff of canonicalized XML" do
        expect(xml1).to be_xml_equivalent_to(xml2)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        # Should show the actual difference in canonicalized form
        expect(e.message).to match(/Line-by-line diff/)
        expect(e.message).to include("attr")
      end
    end

    context "with whitespace normalization" do
      let(:xml1) { "<root>  <a>text</a>  </root>" }
      let(:xml2) { "<root><a>text</a></root>" }

      it "matches XML despite whitespace differences" do
        # Use :normalize to ignore whitespace differences
        expect(xml1).to be_xml_equivalent_to(xml2)
          .with_match(structural_whitespace: :normalize)
      end
    end

    context "with attribute order differences" do
      let(:xml1) { '<root><element a="1" b="2" c="3">text</element></root>' }
      let(:xml2) { '<root><element c="3" b="2" a="1">text</element></root>' }

      it "matches XML despite attribute order differences" do
        expect(xml1).to be_xml_equivalent_to(xml2)
      end
    end

    context "with element-level whitespace sensitivity" do
      let(:xml_with_preserve) do
        '<root><code xml:space="preserve">  indented  </code></root>'
      end
      let(:xml_compact) do
        '<root><code xml:space="preserve">indented</code></root>'
      end

      it "respects xml:space attribute when respect_xml_space is true" do
        expect(xml_with_preserve).not_to be_xml_equivalent_to(
          xml_compact,
          match: { text_content: :strict, respect_xml_space: true },
        )
      end

      it "ignores xml:space attribute when respect_xml_space is false" do
        # When respect_xml_space is false, xml:space is ignored
        # and format defaults apply (XML has none, so whitespace is normalized)
        expect(xml_with_preserve).to be_xml_equivalent_to(
          xml_compact,
          match: { text_content: :normalize, respect_xml_space: false },
        )
      end

      context "with whitespace_sensitive_elements option" do
        let(:xml1) { "<root><code>  indented  </code><p>  text  </p></root>" }
        let(:xml2) { "<root><code>indented</code><p>text</p></root>" }

        it "treats whitelisted elements as whitespace-sensitive" do
          expect(xml1).not_to be_xml_equivalent_to(
            xml2,
            match: {
              text_content: :strict,
              whitespace_sensitive_elements: [:code],
            },
          )
        end

        it "normalizes whitespace for non-sensitive elements" do
          # With text_content: :normalize, non-sensitive elements normalize
          # Only test p elements (not in whitelist) to verify normalization works
          xml3 = "<root><code>  indented  </code><p>text</p></root>"
          xml4 = "<root><code>  indented  </code><p>  text  </p></root>"

          expect(xml3).to be_xml_equivalent_to(
            xml4,
            match: {
              text_content: :normalize,
              whitespace_sensitive_elements: [:code],
            },
          )
        end
      end

      context "with whitespace_insensitive_elements option" do
        let(:html1) do
          "<root><pre>  indented  </pre><code>  code  </code></root>"
        end
        let(:html2) { "<root><pre>  indented  </pre><code>code</code></root>" }

        it "excludes blacklisted elements from default sensitive list for HTML" do
          # HTML defaults: [:pre, :code, :textarea, :script, :style]
          # Excluding :code means it's no longer whitespace-sensitive
          # HTML defaults text_content to :normalize, so non-sensitive elements normalize
          expect(html1).to be_html_equivalent_to(
            html2,
            match: {
              whitespace_insensitive_elements: [:code],
            },
          )
        end
      end
    end
  end

  describe "show_diffs filtering" do
    let(:xml_with_comment1) do
      <<~XML
        <root>
          <!-- Comment A -->
          <element>value1</element>
        </root>
      XML
    end

    let(:xml_with_comment2) do
      <<~XML
        <root>
          <!-- Comment B -->
          <element>value2</element>
        </root>
      XML
    end

    context "with show_diffs chain method" do
      it "accepts :all parameter" do
        matcher = be_xml_equivalent_to(xml_with_comment2).show_diffs(:all)
        expect(matcher).to be_a(Canon::RSpecMatchers::SerializationMatcher)
      end

      it "accepts :normative parameter" do
        matcher = be_xml_equivalent_to(xml_with_comment2).show_diffs(:normative)
        expect(matcher).to be_a(Canon::RSpecMatchers::SerializationMatcher)
      end

      it "accepts :informative parameter" do
        matcher = be_xml_equivalent_to(xml_with_comment2).show_diffs(:informative)
        expect(matcher).to be_a(Canon::RSpecMatchers::SerializationMatcher)
      end
    end

    context "with comments: :ignore" do
      it "shows both normative and informative diffs with show_diffs: :all" do
        expect(xml_with_comment1).to be_xml_equivalent_to(
          xml_with_comment2,
          match: { comments: :ignore },
        ).show_diffs(:all)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        # Should fail because of normative diff (element value)
        expect(e.message).to include("expected XML to be equivalent")
      end

      it "filters to normative diffs only with show_diffs: :normative" do
        expect(xml_with_comment1).to be_xml_equivalent_to(
          xml_with_comment2,
          match: { comments: :ignore },
        ).show_diffs(:normative)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        # Should show normative diffs (element value change)
        expect(e.message).to include("expected XML to be equivalent")
      end

      it "filters to informative diffs only with show_diffs: :informative" do
        # When comments are ignored, comment diffs are informative
        # So documents with only comment diffs are equivalent
        xml1 = "<root><!-- Comment A --><element>same</element></root>"
        xml2 = "<root><!-- Comment B --><element>same</element></root>"

        # These should be equivalent (comments ignored = informative)
        expect(xml1).to be_xml_equivalent_to(
          xml2,
          match: { comments: :ignore },
        ).show_diffs(:informative)
      end
    end

    context "with comments: :strict" do
      it "comment diffs are normative and shown with show_diffs: :normative" do
        xml1 = "<root><!-- Comment A --><element>same</element></root>"
        xml2 = "<root><!-- Comment B --><element>same</element></root>"

        begin
          expect(xml1).to be_xml_equivalent_to(
            xml2,
            match: { comments: :strict },
          ).show_diffs(:normative)
        rescue RSpec::Expectations::ExpectationNotMetError => e
          # Should fail because comment diffs are normative
          expect(e.message).to include("expected XML to be equivalent")
        end
      end
    end

    context "equivalence determination" do
      it "show_diffs does not affect equivalence result" do
        xml1 = "<root><el>A</el></root>"
        xml2 = "<root><el>B</el></root>"

        # All three should fail (not equivalent) regardless of show_diffs
        expect do
          expect(xml1).to be_xml_equivalent_to(xml2).show_diffs(:all)
        end.to raise_error(RSpec::Expectations::ExpectationNotMetError)

        expect do
          expect(xml1).to be_xml_equivalent_to(xml2).show_diffs(:normative)
        end.to raise_error(RSpec::Expectations::ExpectationNotMetError)

        expect do
          expect(xml1).to be_xml_equivalent_to(xml2).show_diffs(:informative)
        end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
      end
    end
  end
end
