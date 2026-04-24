# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Canon::Comparison.summarize" do
  describe "equivalent documents" do
    it "returns 'Equivalent' for identical XML" do
      xml = "<root><item>Hello</item></root>"
      expect(Canon::Comparison.summarize(xml, xml)).to eq("Equivalent")
    end

    it "returns 'Equivalent' for semantically equivalent XML" do
      compact = "<root><a>text</a></root>"
      expanded = "<root>\n  <a>text</a>\n</root>"
      expect(Canon::Comparison.summarize(compact, expanded)).to eq("Equivalent")
    end

    it "returns 'Equivalent' for identical JSON" do
      json1 = '{"a": 1, "b": 2}'
      json2 = '{"a": 1, "b": 2}'
      expect(Canon::Comparison.summarize(json1, json2)).to eq("Equivalent")
    end
  end

  describe "differing documents" do
    it "includes 'Not equivalent' when text content differs" do
      xml1 = "<root><item>Hello</item></root>"
      xml2 = "<root><item>World</item></root>"
      summary = Canon::Comparison.summarize(xml1, xml2)
      expect(summary).to start_with("Not equivalent:")
    end

    it "includes the diff reason" do
      xml1 = "<root><item>Hello</item></root>"
      xml2 = "<root><item>World</item></root>"
      summary = Canon::Comparison.summarize(xml1, xml2)
      # XML comparator produces reasons like 'Text: "Hello" vs "World"'
      expect(summary).to include("Text")
    end

    it "includes the path when available" do
      xml1 = "<p>Hello</p>"
      xml2 = "<p>World</p>"
      summary = Canon::Comparison.summarize(xml1, xml2)
      expect(summary).to include("/p")
    end

    it "shows value preview for text differences" do
      xml1 = "<root><item>Hello</item></root>"
      xml2 = "<root><item>World</item></root>"
      summary = Canon::Comparison.summarize(xml1, xml2)
      expect(summary).to include("Hello")
      expect(summary).to include("World")
      expect(summary).to include("vs")
    end

    it "reports missing nodes" do
      xml1 = "<root><a/><b/></root>"
      xml2 = "<root><a/></root>"
      summary = Canon::Comparison.summarize(xml1, xml2)
      expect(summary).to start_with("Not equivalent:")
    end

    it "reports attribute differences" do
      xml1 = '<root attr="old"/>'
      xml2 = '<root attr="new"/>'
      summary = Canon::Comparison.summarize(xml1, xml2)
      expect(summary).to start_with("Not equivalent:")
    end

    it "works with JSON differences" do
      json1 = '{"key": "value1"}'
      json2 = '{"key": "value2"}'
      summary = Canon::Comparison.summarize(json1, json2)
      expect(summary).to start_with("Not equivalent")
      expect(summary).to include("value1")
      expect(summary).to include("value2")
    end
  end

  describe "regression guard" do
    it "equivalent? still returns plain boolean" do
      xml = "<root><item>Hello</item></root>"
      result = Canon::Comparison.equivalent?(xml, xml)
      expect(result).to be(true)
    end

    it "equivalent? returns false for differing docs" do
      xml1 = "<root><item>Hello</item></root>"
      xml2 = "<root><item>World</item></root>"
      result = Canon::Comparison.equivalent?(xml1, xml2)
      expect(result).to be(false)
    end

    it "accepts same opts as equivalent?" do
      xml1 = "<root><a>text</a></root>"
      xml2 = "<root><a>text</a></root>"
      summary = Canon::Comparison.summarize(xml1, xml2, profile: :strict)
      expect(summary).to eq("Equivalent")
    end
  end
end
