# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Comparison::JsonComparator do
  describe ".equivalent?" do
    context "with identical JSON" do
      it "returns true for simple identical JSON" do
        json1 = '{"key": "value"}'
        json2 = '{"key": "value"}'

        expect(described_class.equivalent?(json1, json2)).to be true
      end

      it "returns true for identical nested structures" do
        json1 = '{"outer": {"inner": "value"}}'
        json2 = '{"outer": {"inner": "value"}}'

        expect(described_class.equivalent?(json1, json2)).to be true
      end

      it "returns true for identical arrays" do
        json1 = "[1, 2, 3]"
        json2 = "[1, 2, 3]"

        expect(described_class.equivalent?(json1, json2)).to be true
      end

      it "returns true when key order differs" do
        json1 = '{"a": 1, "b": 2}'
        json2 = '{"b": 2, "a": 1}'

        expect(described_class.equivalent?(json1, json2)).to be true
      end
    end

    context "with different JSON" do
      it "returns false when hash values differ" do
        json1 = '{"key": "value1"}'
        json2 = '{"key": "value2"}'

        expect(described_class.equivalent?(json1, json2)).to be false
      end

      it "returns false when hash has missing keys" do
        json1 = '{"key1": "value", "key2": "value"}'
        json2 = '{"key1": "value"}'

        expect(described_class.equivalent?(json1, json2)).to be false
      end

      it "returns false when array elements differ" do
        json1 = "[1, 2, 3]"
        json2 = "[1, 2, 4]"

        expect(described_class.equivalent?(json1, json2)).to be false
      end

      it "returns false when array lengths differ" do
        json1 = "[1, 2, 3]"
        json2 = "[1, 2]"

        expect(described_class.equivalent?(json1, json2)).to be false
      end

      it "returns false when types differ" do
        json1 = '{"key": "value"}'
        json2 = '["value"]'

        expect(described_class.equivalent?(json1, json2)).to be false
      end
    end

    context "with hash comparison" do
      it "detects missing keys in second hash" do
        hash1 = { "a" => 1, "b" => 2 }
        hash2 = { "a" => 1 }

        expect(described_class.equivalent?(hash1, hash2)).to be false
      end

      it "detects missing keys in first hash" do
        hash1 = { "a" => 1 }
        hash2 = { "a" => 1, "b" => 2 }

        expect(described_class.equivalent?(hash1, hash2)).to be false
      end

      it "detects different values for same key" do
        hash1 = { "a" => 1, "b" => 2 }
        hash2 = { "a" => 1, "b" => 3 }

        expect(described_class.equivalent?(hash1, hash2)).to be false
      end

      it "handles nested hash comparison" do
        hash1 = { "outer" => { "inner" => 1 } }
        hash2 = { "outer" => { "inner" => 2 } }

        expect(described_class.equivalent?(hash1, hash2)).to be false
      end
    end

    context "with array comparison" do
      it "detects different array lengths" do
        arr1 = [1, 2, 3]
        arr2 = [1, 2]

        expect(described_class.equivalent?(arr1, arr2)).to be false
      end

      it "detects different elements at same position" do
        arr1 = [1, 2, 3]
        arr2 = [1, 9, 3]

        expect(described_class.equivalent?(arr1, arr2)).to be false
      end

      it "handles nested arrays" do
        arr1 = [[1, 2], [3, 4]]
        arr2 = [[1, 2], [3, 5]]

        expect(described_class.equivalent?(arr1, arr2)).to be false
      end

      it "handles arrays of hashes" do
        arr1 = [{ "a" => 1 }, { "b" => 2 }]
        arr2 = [{ "a" => 1 }, { "b" => 3 }]

        expect(described_class.equivalent?(arr1, arr2)).to be false
      end
    end

    context "with primitive comparison" do
      it "compares strings in JSON" do
        json1 = '"test"'
        json2 = '"test"'
        expect(described_class.equivalent?(json1, json2)).to be true

        json3 = '"test1"'
        json4 = '"test2"'
        expect(described_class.equivalent?(json3, json4)).to be false
      end

      it "compares numbers" do
        expect(described_class.equivalent?(42, 42)).to be true
        expect(described_class.equivalent?(42, 43)).to be false
      end

      it "compares booleans" do
        expect(described_class.equivalent?(true, true)).to be true
        expect(described_class.equivalent?(true, false)).to be false
      end

      it "compares null values" do
        expect(described_class.equivalent?(nil, nil)).to be true
        # "null" as JSON string parses to nil
        expect(described_class.equivalent?("null", nil)).to be true
      end
    end

    context "with type mismatches" do
      it "detects string vs number mismatch" do
        # In JSON, "42" is a string, 42 is a number - these should be different types
        json1 = '"42"'  # JSON string
        json2 = "42"    # JSON number
        expect(described_class.equivalent?(json1, json2)).to be false
      end

      it "detects hash vs array mismatch" do
        expect(described_class.equivalent?({ "a" => 1 }, [1])).to be false
      end

      it "detects array vs primitive mismatch" do
        expect(described_class.equivalent?([1], 1)).to be false
      end
    end

    context "with verbose mode" do
      it "returns empty array for equivalent JSON" do
        json1 = '{"key": "value"}'
        json2 = '{"key": "value"}'

        result = described_class.equivalent?(json1, json2, verbose: true)
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).to be_empty
        expect(result.equivalent?).to be true
      end

      it "returns array of differences for different values" do
        json1 = '{"key": "value1"}'
        json2 = '{"key": "value2"}'

        result = described_class.equivalent?(json1, json2, verbose: true)
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false
        expect(result.differences.first[:path]).to eq("key")
        expect(result.differences.first[:value1]).to eq("value1")
        expect(result.differences.first[:value2]).to eq("value2")
      end

      it "returns array of differences for missing keys" do
        json1 = '{"key1": "value", "key2": "value"}'
        json2 = '{"key1": "value"}'

        result = described_class.equivalent?(json1, json2, verbose: true)
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false
        expect(result.differences.any? { |d| d[:path] == "key2" }).to be true
      end

      it "returns array of differences for array elements" do
        json1 = "[1, 2, 3]"
        json2 = "[1, 9, 3]"

        result = described_class.equivalent?(json1, json2, verbose: true)
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false
        expect(result.differences.first[:path]).to eq("[1]")
        expect(result.differences.first[:value1]).to eq(2)
        expect(result.differences.first[:value2]).to eq(9)
      end

      it "returns array of differences for nested structures" do
        json1 = '{"outer": {"inner": 1}}'
        json2 = '{"outer": {"inner": 2}}'

        result = described_class.equivalent?(json1, json2, verbose: true)
        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.differences).not_to be_empty
        expect(result.equivalent?).to be false
        expect(result.differences.first[:path]).to eq("outer.inner")
      end
    end

    context "with key order" do
      it "ignores key order in JSON objects" do
        json1 = '{"b": 2, "a": 1, "c": 3}'
        json2 = '{"a": 1, "c": 3, "b": 2}'

        expect(described_class.equivalent?(json1, json2)).to be true
      end

      it "handles key order in Ruby hashes" do
        # Note: JSON parsing typically maintains insertion order in modern Ruby
        # but the comparison should handle key order appropriately
        hash1 = { "b" => 2, "a" => 1 }
        hash2 = { "a" => 1, "b" => 2 }

        # Key order doesn't matter in JSON objects
        expect(described_class.equivalent?(hash1, hash2)).to be true
      end
    end

    context "with Ruby objects" do
      it "handles pre-parsed Ruby hashes" do
        obj1 = { "key" => "value" }
        obj2 = { "key" => "value" }

        expect(described_class.equivalent?(obj1, obj2)).to be true
      end

      it "handles pre-parsed Ruby arrays" do
        obj1 = [1, 2, 3]
        obj2 = [1, 2, 3]

        expect(described_class.equivalent?(obj1, obj2)).to be true
      end

      it "handles mixed string and Ruby objects" do
        json1 = '{"key": "value"}'
        obj2 = { "key" => "value" }

        expect(described_class.equivalent?(json1, obj2)).to be true
      end
    end

    context "with complex nested structures" do
      it "compares deeply nested structures" do
        json1 = '{"level1": {"level2": {"level3": {"value": 42}}}}'
        json2 = '{"level1": {"level2": {"level3": {"value": 42}}}}'

        expect(described_class.equivalent?(json1, json2)).to be true
      end

      it "detects differences in deeply nested structures" do
        json1 = '{"level1": {"level2": {"level3": {"value": 42}}}}'
        json2 = '{"level1": {"level2": {"level3": {"value": 43}}}}'

        expect(described_class.equivalent?(json1, json2)).to be false
      end

      it "handles arrays of complex objects" do
        json1 = '[{"a": 1, "b": [1, 2]}, {"c": 3}]'
        json2 = '[{"a": 1, "b": [1, 2]}, {"c": 3}]'

        expect(described_class.equivalent?(json1, json2)).to be true
      end
    end
  end
end
