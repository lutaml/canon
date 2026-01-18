# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Comparison::JsonComparer do
  describe ".compare" do
    context "with identical JSON documents" do
      let(:json1) { '{"key":"value"}' }
      let(:json2) { '{"key":"value"}' }

      it "returns true for equivalent documents" do
        result = described_class.compare(json1, json2)
        expect(result).to be true
      end
    end

    context "with parsed hash objects" do
      let(:obj1) { { "key" => "value" } }
      let(:obj2) { { "key" => "value" } }

      it "returns true for equivalent objects" do
        result = described_class.compare(obj1, obj2)
        expect(result).to be true
      end
    end

    context "with different JSON documents" do
      let(:json1) { '{"key":"value1"}' }
      let(:json2) { '{"key":"value2"}' }

      it "returns false for different documents" do
        result = described_class.compare(json1, json2)
        expect(result).to be false
      end
    end

    context "with key order differences" do
      let(:json1) { '{"b":1,"a":2}' }
      let(:json2) { '{"a":2,"b":1}' }

      it "returns false with :strict profile (order matters)" do
        result = described_class.compare(json1, json2, match_profile: :strict)
        expect(result).to be false
      end

      it "returns true with :spec_friendly profile (order ignored)" do
        result = described_class.compare(json1, json2,
                                         match_profile: :spec_friendly)
        expect(result).to be true
      end
    end

    context "with verbose option" do
      let(:json1) { '{"key":"value1"}' }
      let(:json2) { '{"key":"value2"}' }

      it "returns ComparisonResult with differences" do
        result = described_class.compare(json1, json2, verbose: true)
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
      end
    end
  end

  describe ".parse_data" do
    it "parses JSON string into hash" do
      result = described_class.parse_data('{"key":"value"}')
      expect(result).to eq({ "key" => "value" })
    end

    it "returns hash as-is" do
      hash = { "key" => "value" }
      result = described_class.parse_data(hash)
      expect(result).to eq(hash)
    end
  end

  describe ".serialize_data" do
    it "serializes hash to JSON string" do
      hash = { "key" => "value" }
      result = described_class.serialize_data(hash)
      expect(result).to be_a(String)
      expect(result).to include("key")
      expect(result).to include("value")
    end

    it "returns string as-is" do
      str = '{"key":"value"}'
      result = described_class.serialize_data(str)
      expect(result).to eq(str)
    end
  end
end
