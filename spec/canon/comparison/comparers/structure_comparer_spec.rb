# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Comparison::StructureComparer do
  describe ".compare_structures" do
    context "with identical hashes" do
      let(:hash1) { { "key" => "value" } }
      let(:hash2) { { "key" => "value" } }

      it "returns EQUIVALENT" do
        result = described_class.compare_structures(hash1, hash2, {}, [], "")
        expect(result).to eq(Canon::Comparison::EQUIVALENT)
      end
    end

    context "with different hash values" do
      let(:hash1) { { "key" => "value1" } }
      let(:hash2) { { "key" => "value2" } }

      it "returns UNEQUAL_HASH_VALUES" do
        result = described_class.compare_structures(hash1, hash2, {}, [], "")
        expect(result).to eq(Canon::Comparison::UNEQUAL_HASH_VALUES)
      end
    end

    context "with different hash keys" do
      let(:hash1) { { "key1" => "value" } }
      let(:hash2) { { "key2" => "value" } }

      it "returns MISSING_HASH_KEY" do
        result = described_class.compare_structures(hash1, hash2, {}, [], "")
        expect(result).to eq(Canon::Comparison::MISSING_HASH_KEY)
      end
    end

    context "with identical arrays" do
      let(:array1) { %w[item1 item2] }
      let(:array2) { %w[item1 item2] }

      it "returns EQUIVALENT" do
        result = described_class.compare_structures(array1, array2, {}, [], "")
        expect(result).to eq(Canon::Comparison::EQUIVALENT)
      end
    end

    context "with different array lengths" do
      let(:array1) { %w[item1 item2] }
      let(:array2) { %w[item1] }

      it "returns UNEQUAL_ARRAY_LENGTHS" do
        result = described_class.compare_structures(array1, array2, {}, [], "")
        expect(result).to eq(Canon::Comparison::UNEQUAL_ARRAY_LENGTHS)
      end
    end

    context "with type mismatch" do
      let(:obj1) { { "key" => "value" } }
      let(:obj2) { ["value"] }

      it "returns UNEQUAL_TYPES" do
        result = described_class.compare_structures(obj1, obj2, {}, [], "")
        expect(result).to eq(Canon::Comparison::UNEQUAL_TYPES)
      end
    end

    context "with identical primitives" do
      it "returns EQUIVALENT for strings" do
        result = described_class.compare_structures("same", "same", {}, [], "")
        expect(result).to eq(Canon::Comparison::EQUIVALENT)
      end

      it "returns EQUIVALENT for numbers" do
        result = described_class.compare_structures(42, 42, {}, [], "")
        expect(result).to eq(Canon::Comparison::EQUIVALENT)
      end

      it "returns EQUIVALENT for nil" do
        result = described_class.compare_structures(nil, nil, {}, [], "")
        expect(result).to eq(Canon::Comparison::EQUIVALENT)
      end
    end
  end
end
