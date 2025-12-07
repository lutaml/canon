# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Namespace declaration diffs" do
  describe "detecting namespace declaration differences" do
    it "detects removed namespace declarations" do
      xml1 = '<ownedEnd xmlns:xmi="http://www.omg.org/spec/XMI/20131001" type="test"/>'
      xml2 = '<ownedEnd type="test"/>'

      result = Canon::Comparison::XmlComparator.equivalent?(xml1, xml2, verbose: true)

      expect(result).to be_a(Canon::Comparison::ComparisonResult)
      expect(result.differences).not_to be_empty

      # Find the namespace_declarations difference
      ns_diff = result.differences.find { |d| d.dimension == :namespace_declarations }
      expect(ns_diff).not_to be_nil
      expect(ns_diff.dimension).to eq(:namespace_declarations)
    end

    it "detects added namespace declarations" do
      xml1 = '<ownedEnd type="test"/>'
      xml2 = '<ownedEnd xmlns:xmi="http://www.omg.org/spec/XMI/20131001" type="test"/>'

      result = Canon::Comparison::XmlComparator.equivalent?(xml1, xml2, verbose: true)

      expect(result).to be_a(Canon::Comparison::ComparisonResult)
      expect(result.differences).not_to be_empty

      # Find the namespace_declarations difference
      ns_diff = result.differences.find { |d| d.dimension == :namespace_declarations }
      expect(ns_diff).not_to be_nil
      expect(ns_diff.dimension).to eq(:namespace_declarations)
    end

    it "detects changed namespace URIs" do
      xml1 = '<ownedEnd xmlns:xmi="http://www.omg.org/spec/XMI/20131001" type="test"/>'
      xml2 = '<ownedEnd xmlns:xmi="http://www.omg.org/spec/XMI/20111001" type="test"/>'

      result = Canon::Comparison::XmlComparator.equivalent?(xml1, xml2, verbose: true)

      expect(result).to be_a(Canon::Comparison::ComparisonResult)
      expect(result.differences).not_to be_empty

      # Find the namespace_declarations difference
      ns_diff = result.differences.find { |d| d.dimension == :namespace_declarations }
      expect(ns_diff).not_to be_nil
      expect(ns_diff.dimension).to eq(:namespace_declarations)
    end

    it "reports namespace declarations separately from data attributes" do
      xml1 = '<ownedEnd xmlns:xmi="http://www.omg.org/spec/XMI/20131001" xmi:type="xmi_type" xmi:id="my_id" type="test"/>'
      xml2 = '<ownedEnd xmi:id="my_id" xmi:type="xmi_type" type="test"/>'

      result = Canon::Comparison::XmlComparator.equivalent?(xml1, xml2, verbose: true)

      expect(result).to be_a(Canon::Comparison::ComparisonResult)
      expect(result.differences).not_to be_empty

      # Should have a namespace_declarations difference
      ns_diff = result.differences.find { |d| d.dimension == :namespace_declarations }
      expect(ns_diff).not_to be_nil

      # Should NOT have an attribute_presence difference for data attributes
      # (all data attributes are the same: xmi:id, xmi:type, type)
      attr_presence_diff = result.differences.find { |d| d.dimension == :attribute_presence }
      expect(attr_presence_diff).to be_nil
    end

    it "handles multiple namespace prefixes" do
      xml1 = '<root xmlns:xmi="http://xmi.com" xmlns:uml="http://uml.com" xmlns:xsi="http://xsi.com"/>'
      xml2 = '<root xmlns:xmi="http://xmi.com" xmlns:uml="http://uml.com"/>'

      result = Canon::Comparison::XmlComparator.equivalent?(xml1, xml2, verbose: true)

      expect(result).to be_a(Canon::Comparison::ComparisonResult)
      expect(result.differences).not_to be_empty

      # Find the namespace_declarations difference
      ns_diff = result.differences.find { |d| d.dimension == :namespace_declarations }
      expect(ns_diff).not_to be_nil
      expect(ns_diff.dimension).to eq(:namespace_declarations)
    end

    it "considers elements equivalent when namespace declarations are identical" do
      xml1 = '<ownedEnd xmlns:xmi="http://www.omg.org/spec/XMI/20131001" type="test"/>'
      xml2 = '<ownedEnd xmlns:xmi="http://www.omg.org/spec/XMI/20131001" type="test"/>'

      result = Canon::Comparison::XmlComparator.equivalent?(xml1, xml2, verbose: true)

      expect(result).to be_a(Canon::Comparison::ComparisonResult)

      # Should have no namespace_declarations differences
      ns_diff = result.differences.find { |d| d.dimension == :namespace_declarations }
      expect(ns_diff).to be_nil
    end
  end

  describe "semantic diff report formatting" do
    it "formats namespace declaration differences correctly" do
      xml1 = '<ownedEnd xmlns:xmi="http://www.omg.org/spec/XMI/20131001" type="test"/>'
      xml2 = '<ownedEnd type="test"/>'

      result = Canon::Comparison::XmlComparator.equivalent?(xml1, xml2, verbose: true)
      output = Canon::DiffFormatter::DiffDetailFormatter.format_report(result.differences, use_color: false)

      # Should mention namespace_declarations dimension
      expect(output).to include("namespace_declarations")

      # Should show the removed namespace declaration
      expect(output).to include("xmlns:xmi")
      expect(output).to include("http://www.omg.org/spec/XMI/20131001")
    end

    it "formats added namespace declarations" do
      xml1 = '<ownedEnd type="test"/>'
      xml2 = '<ownedEnd xmlns:xmi="http://www.omg.org/spec/XMI/20131001" type="test"/>'

      result = Canon::Comparison::XmlComparator.equivalent?(xml1, xml2, verbose: true)
      output = Canon::DiffFormatter::DiffDetailFormatter.format_report(result.differences, use_color: false)

      # Should mention namespace_declarations dimension
      expect(output).to include("namespace_declarations")

      # Should show the added namespace declaration
      expect(output).to include("xmlns:xmi")
      expect(output).to include("http://www.omg.org/spec/XMI/20131001")
    end

    it "formats changed namespace URIs" do
      xml1 = '<ownedEnd xmlns:xmi="http://www.omg.org/spec/XMI/20131001" type="test"/>'
      xml2 = '<ownedEnd xmlns:xmi="http://www.omg.org/spec/XMI/20111001" type="test"/>'

      result = Canon::Comparison::XmlComparator.equivalent?(xml1, xml2, verbose: true)
      output = Canon::DiffFormatter::DiffDetailFormatter.format_report(result.differences, use_color: false)

      # Should mention namespace_declarations dimension
      expect(output).to include("namespace_declarations")

      # Should show both URIs
      expect(output).to include("http://www.omg.org/spec/XMI/20131001")
      expect(output).to include("http://www.omg.org/spec/XMI/20111001")
    end
  end

  describe "namespace declarations vs data attributes separation" do
    it "excludes xmlns attributes from data attribute comparison" do
      xml1 = '<element xmlns:ns="http://example.com" ns:attr="value" data="test"/>'
      xml2 = '<element ns:attr="value" data="test"/>'

      result = Canon::Comparison::XmlComparator.equivalent?(xml1, xml2, verbose: true)

      # Should have namespace_declarations difference
      ns_diff = result.differences.find { |d| d.dimension == :namespace_declarations }
      expect(ns_diff).not_to be_nil

      # Should NOT have attribute_presence difference for data attributes
      # (ns:attr and data are present in both)
      attr_presence_diff = result.differences.find { |d| d.dimension == :attribute_presence }
      expect(attr_presence_diff).to be_nil
    end

    it "correctly handles attribute order when namespace declarations are present" do
      xml1 = '<element xmlns:ns="http://example.com" data="test" ns:attr="value"/>'
      xml2 = '<element xmlns:ns="http://example.com" ns:attr="value" data="test"/>'

      # With strict attribute order
      result = Canon::Comparison::XmlComparator.equivalent?(
        xml1, xml2,
        verbose: true,
        match: { attribute_order: :strict }
      )

      # Should have attribute_order difference (data attributes in different order)
      attr_order_diff = result.differences.find { |d| d.dimension == :attribute_order }
      expect(attr_order_diff).not_to be_nil

      # Should NOT have namespace_declarations difference (same xmlns:ns)
      ns_diff = result.differences.find { |d| d.dimension == :namespace_declarations }
      expect(ns_diff).to be_nil
    end
  end
end