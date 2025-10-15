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
        expect(xml1).to be_xml_equivalent_to(xml2)
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
      @original_diff_mode = described_class.diff_mode
      @original_use_color = described_class.use_color
    end

    after do
      # Restore original configuration
      described_class.diff_mode = @original_diff_mode
      described_class.use_color = @original_use_color
    end

    it "allows configuration via configure block" do
      described_class.configure do |config|
        config.diff_mode = :by_object
        config.use_color = false
      end

      expect(described_class.diff_mode).to eq(:by_object)
      expect(described_class.use_color).to be(false)
    end

    it "has default configuration" do
      described_class.reset_config

      expect(described_class.diff_mode).to eq(:by_line)
      expect(described_class.use_color).to be(true)
    end

    it "can be configured for by_object diff mode" do
      described_class.configure do |config|
        config.diff_mode = :by_object
      end

      expect(described_class.diff_mode).to eq(:by_object)
    end

    it "can be configured to disable colors" do
      described_class.configure do |config|
        config.use_color = false
      end

      expect(described_class.use_color).to be(false)
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
        expect(e.message).to include("Line-by-line diff:")
        expect(e.message).to include("attr1")
      end

      it "shows line numbers in diff" do
        expect(xml1).to be_xml_equivalent_to(xml2)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        # Should have line numbers like "  1|  1  |"
        expect(e.message).to match(/\d+\|\s+\d+/)
      end
    end

    context "with missing attributes in XML" do
      let(:xml1) { '<root><element id="A">text</element></root>' }
      let(:xml2) { '<root><element id="A" extra="value">text</element></root>' }

      it "highlights missing attributes in diff" do
        expect(xml1).to be_xml_equivalent_to(xml2)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to include("Line-by-line diff:")
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
        expect(e.message).to include("Line-by-line diff:")
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
        expect(e.message).to include("Line-by-line diff:")
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
        expect(e.message).to include("Line-by-line diff:")
      end
    end

    context "when configured for by_object mode" do
      before do
        described_class.configure do |config|
          config.diff_mode = :by_object
        end
      end

      after do
        described_class.reset_config
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

  describe "regression prevention" do
    # These tests ensure the visual diff behavior doesn't regress

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
        expect(e.message).to include("Line-by-line diff:")
        expect(e.message).to include("attr")
      end
    end

    context "with whitespace normalization" do
      let(:xml1) { "<root>  <a>text</a>  </root>" }
      let(:xml2) { "<root><a>text</a></root>" }

      it "matches XML despite whitespace differences" do
        expect(xml1).to be_xml_equivalent_to(xml2)
      end
    end

    context "with attribute order differences" do
      let(:xml1) { '<root><element a="1" b="2" c="3">text</element></root>' }
      let(:xml2) { '<root><element c="3" b="2" a="1">text</element></root>' }

      it "matches XML despite attribute order differences" do
        expect(xml1).to be_xml_equivalent_to(xml2)
      end
    end

    context "with complex nested structures" do
      let(:xml1) do
        <<~XML
          <root>
            <parent id="p1">
              <child id="c1" attr="value1">
                <grandchild>text1</grandchild>
              </child>
            </parent>
          </root>
        XML
      end

      let(:xml2) do
        <<~XML
          <root>
            <parent id="p1">
              <child id="c1" attr="value2">
                <grandchild>text1</grandchild>
              </child>
            </parent>
          </root>
        XML
      end

      it "shows precise location of difference in nested structure" do
        expect(xml1).to be_xml_equivalent_to(xml2)
      rescue RSpec::Expectations::ExpectationNotMetError => e
        expect(e.message).to include("Line-by-line diff:")
        expect(e.message).to include("attr")
        expect(e.message).to include("value1")
        expect(e.message).to include("value2")
      end
    end
  end
end
