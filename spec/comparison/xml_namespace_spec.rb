# frozen_string_literal: true

require "spec_helper"

RSpec.describe "XML namespace comparison" do
  describe "different namespace URIs on same element name" do
    it "detects when namespace is on parent vs child element" do
      xml1 = <<~XML
        <Unit xmlns="https://schema.example.org/units/1.0" id="U_m.kg-2">
          <UnitSymbol type="MathML">
            <math xmlns="http://www.w3.org/1998/Math/MathML">x+y</math>
          </UnitSymbol>
        </Unit>
      XML

      xml2 = <<~XML
        <Unit xmlns="https://schema.example.org/units/1.0" id="U_m.kg-2">
          <UnitSymbol xmlns="http://www.w3.org/1998/Math/MathML" type="MathML">
            <math>x+y</math>
          </UnitSymbol>
        </Unit>
      XML

      # These should NOT be equivalent - UnitSymbol has different namespace URIs
      result = Canon::Comparison::XmlComparator.equivalent?(xml1, xml2, verbose: true)

      expect(result.differences).not_to be_empty
      expect(result.differences.any?(&:normative?)).to be true

      # In XML1: UnitSymbol has namespace https://schema.example.org/units/1.0 (inherited)
      # In XML2: UnitSymbol has namespace http://www.w3.org/1998/Math/MathML (explicit)
      # These are different elements!
    end

    it "considers elements with same name but different namespaces as different" do
      xml1 = <<~XML
        <root xmlns="http://example.org/ns1">
          <child>content</child>
        </root>
      XML

      xml2 = <<~XML
        <root xmlns="http://example.org/ns2">
          <child>content</child>
        </root>
      XML

      result = Canon::Comparison::XmlComparator.equivalent?(xml1, xml2, verbose: true)

      expect(result.differences).not_to be_empty
      expect(result.differences.any?(&:normative?)).to be true
    end

    it "considers elements equivalent when they have the same namespace URI" do
      xml1 = <<~XML
        <root xmlns="http://example.org/ns1">
          <child>content</child>
        </root>
      XML

      xml2 = <<~XML
        <root xmlns="http://example.org/ns1">
          <child>content</child>
        </root>
      XML

      result = Canon::Comparison::XmlComparator.equivalent?(xml1, xml2)

      expect(result).to be true
    end
  end
end
