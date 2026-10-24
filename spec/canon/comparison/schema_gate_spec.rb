# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Comparison::SchemaGate do
  let(:schema_xsd) do
    <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="note">
          <xs:complexType>
            <xs:sequence>
              <xs:element name="to" type="xs:string"/>
              <xs:element name="from" type="xs:string"/>
              <xs:element name="body" type="xs:string" minOccurs="0"/>
            </xs:sequence>
          </xs:complexType>
        </xs:element>
      </xs:schema>
    XSD
  end

  let(:valid_a) { "<note><to>A</to><from>B</from></note>" }
  let(:valid_b) { "<note><to>A</to><from>B</from><body>x</body></note>" }
  let(:invalid) { "<note><from>B</from></note>" }

  describe ".gate" do
    it "returns empty when both documents pass the schema" do
      expect(described_class.gate(valid_a, valid_b, schema_xsd)).to eq({})
    end

    it "reports the failing side" do
      failures = described_class.gate(valid_a, invalid, schema_xsd)
      expect(failures.keys).to eq([1])
      expect(failures[1]).to be_a(Canon::ValidationError)
    end

    it "accepts a compiled schema" do
      compiled = Canon::Validators::XsdValidator.compile(schema_xsd)
      expect(described_class.gate(valid_a, valid_b, compiled)).to eq({})
    end
  end

  describe "the validate-then-compare mode" do
    it "keeps schema-valid documents equivalent" do
      expect(Canon::Comparison.equivalent?(valid_a, valid_b, xsd: schema_xsd,
                                                             ignore_children: [:body]))
        .to be(true)
    end

    it "fails the comparison when either side fails the schema" do
      expect(Canon::Comparison.equivalent?(valid_a, invalid, xsd: schema_xsd)).to be(false)
      expect(Canon::Comparison.equivalent?(invalid, valid_a, xsd: schema_xsd)).to be(false)
    end

    it "carries the engine's failure as the difference reason (verbose)" do
      result = Canon::Comparison.equivalent?(invalid, valid_a, xsd: schema_xsd, verbose: true)
      expect(result).to be_a(Canon::Comparison::ComparisonResult)
      expect(result).not_to be_equivalent
      expect(result.differences.first.dimension).to eq(:schema_validation)
      expect(result.differences.first.reason).to include("note")
    end

    it "still compares content when both sides are schema-valid" do
      expect(Canon::Comparison.equivalent?(valid_a, valid_b, xsd: schema_xsd)).to be(false)
    end
  end

  describe "schema compilation errors" do
    it "raises when the document is not a schema" do
      expect { Canon::Validators::XsdValidator.compile("<foo/>") }
        .to raise_error(Canon::ValidationError, /schema invalid/)
    end
  end
end
