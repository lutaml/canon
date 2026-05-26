# frozen_string_literal: true

require "spec_helper"
require "canon/comparison"
require "canon/diff_formatter"
require "canon/diff_formatter/diff_detail_formatter"

RSpec.describe "XML attribute difference handling" do
  def compare(xml1, xml2, **opts)
    Canon::Comparison.equivalent?(xml1, xml2,
                                  { format: :xml, verbose: true }.merge(opts))
  end

  def visual_diff(result)
    formatter = Canon::DiffFormatter.new(use_color: false, mode: :by_object)
    formatter.format(result, :xml)
  end

  def semantic_report(result)
    Canon::DiffFormatter::DiffDetailFormatter.format_report(
      result.differences, use_color: false
    )
  end

  # --- Attribute value detection ---

  describe "attribute value differences" do
    it "detects single attribute value change" do
      result = compare(
        '<element id="1">text</element>',
        '<element id="2">text</element>',
      )
      expect(result.equivalent?).to be false
      attr_diffs = result.differences.select do |d|
        d.dimension == :attribute_values
      end
      expect(attr_diffs.length).to eq(1)
      expect(attr_diffs.first.reason).to include("id")
    end

    it "detects multiple attribute value changes in one element" do
      result = compare(
        '<element id="1" name="foo">text</element>',
        '<element id="2" name="bar">text</element>',
      )
      expect(result.equivalent?).to be false
      attr_diffs = result.differences.select do |d|
        d.dimension == :attribute_values
      end
      expect(attr_diffs.length).to eq(1)
      # Reason should mention both changed attributes
      reason = attr_diffs.first.reason
      expect(reason).to include("id")
      expect(reason).to include("name")
    end

    it "produces a specific reason showing which attributes changed" do
      result = compare(
        '<element id="1">text</element>',
        '<element id="2">text</element>',
      )
      diff = result.differences.find { |d| d.dimension == :attribute_values }
      expect(diff.reason).to eq('Attributes differ (Changed: id="1" → "2")')
    end

    it "stores attribute_before and attribute_after in the DiffNode" do
      result = compare(
        '<element id="1" name="foo">text</element>',
        '<element id="2" name="bar">text</element>',
      )
      diff = result.differences.find { |d| d.dimension == :attribute_values }
      expect(diff.attributes_before).to include("id" => "1", "name" => "foo")
      expect(diff.attributes_after).to include("id" => "2", "name" => "bar")
    end

    it "shows specific attribute values in visual tree output" do
      result = compare(
        '<element id="1" name="foo">text</element>',
        '<element id="2" name="bar">text</element>',
      )
      output = visual_diff(result)
      expect(output).to include("id: 1 → 2")
      expect(output).to include("name: foo → bar")
    end

    it "shows specific attribute values in semantic diff report" do
      result = compare(
        '<element id="1" name="foo">text</element>',
        '<element id="2" name="bar">text</element>',
      )
      report = semantic_report(result)
      expect(report).to include("id:")
      expect(report).to include("name:")
      expect(report).to include('"1" → "2"')
      expect(report).to include('"foo" → "bar"')
    end
  end

  # --- Attribute presence detection ---

  describe "attribute presence differences" do
    it "detects missing attributes" do
      result = compare(
        '<element id="1" name="foo">text</element>',
        '<element id="1">text</element>',
      )
      expect(result.equivalent?).to be false
      diff = result.differences.find { |d| d.dimension == :attribute_presence }
      expect(diff).not_to be_nil
      expect(diff.reason).to include("name")
    end

    it "detects added attributes" do
      result = compare(
        '<element id="1">text</element>',
        '<element id="1" name="foo">text</element>',
      )
      expect(result.equivalent?).to be false
      diff = result.differences.find { |d| d.dimension == :attribute_presence }
      expect(diff).not_to be_nil
      expect(diff.reason).to include("name")
    end

    it "shows added/removed attributes in visual tree output" do
      result = compare(
        '<element id="1" extra="bar">text</element>',
        '<element id="1">text</element>',
      )
      output = visual_diff(result)
      expect(output).to include('- extra="bar"')
    end
  end

  # --- Attribute order ---

  describe "attribute order differences" do
    it "ignores attribute order by default (attribute_order: :ignore)" do
      result = compare(
        '<element id="1" name="foo">text</element>',
        '<element name="foo" id="1">text</element>',
      )
      expect(result.equivalent?).to be true
    end

    it "detects attribute order as informative when strict" do
      result = compare(
        '<element id="1" name="foo">text</element>',
        '<element name="foo" id="1">text</element>',
        match: { attribute_order: :strict },
      )
      expect(result.equivalent?).to be false
      diff = result.differences.find { |d| d.dimension == :attribute_order }
      expect(diff).not_to be_nil
    end
  end

  # --- Combined attribute + content differences ---

  describe "combined attribute and content differences" do
    it "reports both attribute and text content differences" do
      result = compare(
        '<element id="1">Hello</element>',
        '<element id="2">Goodbye</element>',
      )
      expect(result.equivalent?).to be false
      dimensions = result.differences.map(&:dimension)
      expect(dimensions).to include(:attribute_values)
      expect(dimensions).to include(:text_content)
    end

    it "shows both differences in visual tree output" do
      result = compare(
        '<element id="1">Hello</element>',
        '<element id="2">Goodbye</element>',
      )
      output = visual_diff(result)
      expect(output).to include("id: 1 → 2")
      expect(output).to include('"Hello"')
      expect(output).to include('"Goodbye"')
    end
  end

  # --- Nested attribute differences ---

  describe "nested attribute differences" do
    it "shows attribute differences at correct nesting level" do
      result = compare(
        '<root><parent><child id="1">text</child></parent></root>',
        '<root><parent><child id="2">text</child></parent></root>',
      )
      output = visual_diff(result)
      expect(output).to include("child")
      expect(output).to include("id: 1 → 2")
    end

    it "shows attribute differences for multiple elements" do
      result = compare(
        '<root><a id="1"/><b id="2"/></root>',
        '<root><a id="10"/><b id="20"/></root>',
      )
      output = visual_diff(result)
      expect(output).to include("id: 1 → 10")
      expect(output).to include("id: 2 → 20")
    end
  end

  # --- DiffFormatter integration ---

  describe "DiffFormatter output quality" do
    it "prints 'Visual Diff:' exactly once" do
      result = compare(
        '<element id="1">text</element>',
        '<element id="2">text</element>',
      )
      output = visual_diff(result)
      count = output.scan("Visual Diff:").length
      expect(count).to eq(1)
    end

    it "does not show bare 'attributes differ' without specifics" do
      result = compare(
        '<element id="1">text</element>',
        '<element id="2">text</element>',
      )
      output = visual_diff(result)
      # Should NOT contain the vague "[attribute_values: attributes differ]"
      # Should contain specific attribute info instead
      expect(output).not_to match(/\[attribute_values:\s*attributes differ\]/)
      expect(output).to include("id:")
    end
  end
end
