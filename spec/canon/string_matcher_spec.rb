# frozen_string_literal: true

require "spec_helper"

RSpec.describe "String matcher", type: :matcher do
  describe "be_equivalent_to with auto-detection" do
    context "when content is XML" do
      it "detects XML format and uses XML mode" do
        xml1 = "<root><child>value</child></root>"
        xml2 = "<root>\n  <child>value</child>\n</root>"

        expect(xml1).to be_equivalent_to(xml2)
      end

      it "shows XML mode in diff when failing" do
        xml1 = "<root><child>value1</child></root>"
        xml2 = "<root><child>value2</child></root>"

        expect do
          expect(xml1).to be_equivalent_to(xml2)
        end.to raise_error(RSpec::Expectations::ExpectationNotMetError, /XML mode/)
      end
    end

    context "when content is JSON" do
      it "detects JSON format and uses JSON mode" do
        json1 = '{"key": "value"}'
        json2 = '{ "key" : "value" }'

        expect(json1).to be_equivalent_to(json2)
      end

      it "shows JSON mode in diff when failing" do
        json1 = '{"key": "value1"}'
        json2 = '{"key": "value2"}'

        expect do
          expect(json1).to be_equivalent_to(json2)
        end.to raise_error(RSpec::Expectations::ExpectationNotMetError, /JSON mode/)
      end
    end

    context "when content is YAML" do
      it "detects YAML format and uses YAML mode" do
        yaml1 = "key: value"
        yaml2 = "key:  value"

        expect(yaml1).to be_equivalent_to(yaml2)
      end

      it "shows YAML mode in diff when failing" do
        yaml1 = "key: value1"
        yaml2 = "key: value2"

        expect do
          expect(yaml1).to be_equivalent_to(yaml2)
        end.to raise_error(RSpec::Expectations::ExpectationNotMetError, /YAML mode/)
      end
    end

    context "when content is plain string (fallback)" do
      it "falls back to string mode for plain text" do
        str1 = "Hello World"
        str2 = "Hello World"

        expect(str1).to be_equivalent_to(str2)
      end

      it "shows STRING mode in diff when failing" do
        str1 = "Hello World"
        str2 = "Hello Universe"

        expect do
          expect(str1).to be_equivalent_to(str2)
        end.to raise_error(RSpec::Expectations::ExpectationNotMetError, /STRING mode/)
      end

      it "detects differences in plain strings" do
        str1 = "Hello World"
        str2 = "Hello Universe"

        expect(str1).not_to be_equivalent_to(str2)
      end
    end
  end

  describe "be_string_equivalent_to with explicit string mode" do
    it "matches identical strings" do
      expect("Hello World").to be_string_equivalent_to("Hello World")
    end

    it "detects string differences" do
      expect("Hello World").not_to be_string_equivalent_to("Hello Universe")
    end

    it "shows STRING mode in diff" do
      expect do
        expect("Hello World").to be_string_equivalent_to("Hello Universe")
      end.to raise_error(RSpec::Expectations::ExpectationNotMetError, /STRING mode/)
    end

    context "with whitespace differences" do
      it "detects extra spaces" do
        str1 = "Hello World"
        str2 = "Hello  World"  # Two spaces

        expect(str1).not_to be_string_equivalent_to(str2)
      end

      it "detects trailing spaces" do
        str1 = "Hello World"
        str2 = "Hello World "

        expect(str1).not_to be_string_equivalent_to(str2)
      end

      it "visualizes whitespace in diff" do
        str1 = "Hello World"
        str2 = "Hello  World"

        expect do
          expect(str1).to be_string_equivalent_to(str2)
        end.to raise_error(RSpec::Expectations::ExpectationNotMetError, /░/)
      end
    end

    context "with Unicode characters" do
      it "detects non-breaking space vs regular space" do
        str1 = "Hello World"
        str2 = "Hello\u00A0World"  # Non-breaking space

        expect(str1).not_to be_string_equivalent_to(str2)
      end

      it "shows Unicode legend for non-ASCII characters" do
        str1 = "Hello World"
        str2 = "Hello\u00A0World"

        expect do
          expect(str1).to be_string_equivalent_to(str2)
        end.to raise_error(RSpec::Expectations::ExpectationNotMetError,
                           /Character Visualization Legend/)
      end

      it "visualizes non-breaking space" do
        str1 = "Hello World"
        str2 = "Hello\u00A0World"

        expect do
          expect(str1).to be_string_equivalent_to(str2)
        end.to raise_error(RSpec::Expectations::ExpectationNotMetError, /␣/)
      end

      it "detects zero-width space" do
        str1 = "HelloWorld"
        str2 = "Hello\u200BWorld"  # Zero-width space

        expect(str1).not_to be_string_equivalent_to(str2)
      end

      it "visualizes zero-width space" do
        str1 = "HelloWorld"
        str2 = "Hello\u200BWorld"

        expect do
          expect(str1).to be_string_equivalent_to(str2)
        end.to raise_error(RSpec::Expectations::ExpectationNotMetError, /→/)
      end
    end

    context "with multi-line strings" do
      it "matches identical multi-line strings" do
        str1 = "Line 1\nLine 2\nLine 3"
        str2 = "Line 1\nLine 2\nLine 3"

        expect(str1).to be_string_equivalent_to(str2)
      end

      it "detects differences in multi-line strings" do
        str1 = "Line 1\nLine 2\nLine 3"
        str2 = "Line 1\nLine 2 Modified\nLine 3"

        expect(str1).not_to be_string_equivalent_to(str2)
      end

      it "shows line-by-line diff for multi-line strings" do
        str1 = "Line 1\nLine 2\nLine 3"
        str2 = "Line 1\nLine 2 Modified\nLine 3"

        expect do
          expect(str1).to be_string_equivalent_to(str2)
        end.to raise_error(RSpec::Expectations::ExpectationNotMetError,
                           /Line 2/)
      end
    end

    context "with tabs" do
      it "detects tab vs spaces" do
        str1 = "Hello\tWorld"
        str2 = "Hello World"

        expect(str1).not_to be_string_equivalent_to(str2)
      end

      it "visualizes tabs" do
        str1 = "Hello\tWorld"
        str2 = "Hello World"

        expect do
          expect(str1).to be_string_equivalent_to(str2)
        end.to raise_error(RSpec::Expectations::ExpectationNotMetError, /⇥/)
      end
    end

    context "with mixed invisible characters" do
      it "detects multiple types of invisible characters" do
        str1 = "Hello World"
        str2 = "Hello\u00A0\u200BWorld"  # nbsp + zero-width space

        expect(str1).not_to be_string_equivalent_to(str2)
      end

      it "shows legend for all detected characters" do
        str1 = "Hello World"
        str2 = "Hello\u00A0\u200BWorld"

        expect do
          expect(str1).to be_string_equivalent_to(str2)
        end.to raise_error do |error|
          expect(error.message).to include("Character Visualization Legend")
          expect(error.message).to include("U+00A0")
          expect(error.message).to include("U+200B")
        end
      end
    end
  end

  describe "format detection logic" do
    it "detects XML with leading whitespace" do
      xml = "  <root></root>"
      matcher = Canon::RSpecMatchers::SerializationMatcher.new(xml, nil)
      expect(matcher.instance_variable_get(:@format)).to eq(:xml)
    end

    it "detects JSON arrays" do
      json = "[1, 2, 3]"
      matcher = Canon::RSpecMatchers::SerializationMatcher.new(json, nil)
      expect(matcher.instance_variable_get(:@format)).to eq(:json)
    end

    it "detects JSON objects" do
      json = '{"key": "value"}'
      matcher = Canon::RSpecMatchers::SerializationMatcher.new(json, nil)
      expect(matcher.instance_variable_get(:@format)).to eq(:json)
    end

    it "detects YAML" do
      yaml = "key: value"
      matcher = Canon::RSpecMatchers::SerializationMatcher.new(yaml, nil)
      expect(matcher.instance_variable_get(:@format)).to eq(:yaml)
    end

    it "falls back to string for ambiguous content" do
      text = "Just some plain text"
      matcher = Canon::RSpecMatchers::SerializationMatcher.new(text, nil)
      expect(matcher.instance_variable_get(:@format)).to eq(:string)
    end
  end
end
