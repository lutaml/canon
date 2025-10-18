# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Comparison::YamlComparator do
  describe ".equivalent?" do
    context "with identical YAML" do
      it "returns true for simple identical YAML" do
        yaml1 = "key: value"
        yaml2 = "key: value"

        expect(described_class.equivalent?(yaml1, yaml2)).to be true
      end

      it "returns true for identical nested structures" do
        yaml1 = <<~YAML
          outer:
            inner: value
        YAML
        yaml2 = <<~YAML
          outer:
            inner: value
        YAML

        expect(described_class.equivalent?(yaml1, yaml2)).to be true
      end

      it "returns true for identical arrays" do
        yaml1 = <<~YAML
          - 1
          - 2
          - 3
        YAML
        yaml2 = <<~YAML
          - 1
          - 2
          - 3
        YAML

        expect(described_class.equivalent?(yaml1, yaml2)).to be true
      end

      it "returns true when key order differs with ignore_attr_order" do
        yaml1 = <<~YAML
          a: 1
          b: 2
        YAML
        yaml2 = <<~YAML
          b: 2
          a: 1
        YAML

        expect(described_class.equivalent?(yaml1, yaml2, ignore_attr_order: true)).to be true
      end
    end

    context "with different YAML" do
      it "returns false when values differ" do
        yaml1 = "key: value1"
        yaml2 = "key: value2"

        expect(described_class.equivalent?(yaml1, yaml2)).to be false
      end

      it "returns false when hash has missing keys" do
        yaml1 = <<~YAML
          key1: value
          key2: value
        YAML
        yaml2 = "key1: value"

        expect(described_class.equivalent?(yaml1, yaml2)).to be false
      end

      it "returns false when array elements differ" do
        yaml1 = <<~YAML
          - 1
          - 2
          - 3
        YAML
        yaml2 = <<~YAML
          - 1
          - 2
          - 4
        YAML

        expect(described_class.equivalent?(yaml1, yaml2)).to be false
      end

      it "returns false when array lengths differ" do
        yaml1 = <<~YAML
          - 1
          - 2
          - 3
        YAML
        yaml2 = <<~YAML
          - 1
          - 2
        YAML

        expect(described_class.equivalent?(yaml1, yaml2)).to be false
      end
    end

    context "with YAML-specific features" do
      it "handles multi-line strings" do
        yaml1 = <<~YAML
          text: |
            This is a
            multi-line string
        YAML
        yaml2 = <<~YAML
          text: |
            This is a
            multi-line string
        YAML

        expect(described_class.equivalent?(yaml1, yaml2)).to be true
      end

      it "handles YAML anchors and aliases" do
        yaml1 = <<~YAML
          base: &base
            key: value
          derived:
            <<: *base
        YAML
        # The parsed result should be equivalent to explicit structure
        yaml2 = <<~YAML
          base:
            key: value
          derived:
            key: value
        YAML

        expect(described_class.equivalent?(yaml1, yaml2)).to be true
      end

      it "handles YAML booleans" do
        yaml1 = "enabled: true"
        yaml2 = "enabled: true"

        expect(described_class.equivalent?(yaml1, yaml2)).to be true
      end

      it "handles YAML null values" do
        yaml1 = "value: null"
        yaml2 = "value: null"

        expect(described_class.equivalent?(yaml1, yaml2)).to be true
      end
    end

    context "with verbose mode" do
      it "returns empty array for equivalent YAML" do
        yaml1 = "key: value"
        yaml2 = "key: value"

        result = described_class.equivalent?(yaml1, yaml2, verbose: true)
        expect(result).to be_an(Array)
        expect(result).to be_empty
      end

      it "returns array of differences for different values" do
        yaml1 = "key: value1"
        yaml2 = "key: value2"

        result = described_class.equivalent?(yaml1, yaml2, verbose: true)
        expect(result).to be_an(Array)
        expect(result).not_to be_empty
        expect(result.first[:path]).to eq("key")
        expect(result.first[:value1]).to eq("value1")
        expect(result.first[:value2]).to eq("value2")
      end

      it "returns array of differences for missing keys" do
        yaml1 = <<~YAML
          key1: value
          key2: value
        YAML
        yaml2 = "key1: value"

        result = described_class.equivalent?(yaml1, yaml2, verbose: true)
        expect(result).to be_an(Array)
        expect(result).not_to be_empty
        expect(result.any? { |d| d[:path] == "key2" }).to be true
      end

      it "returns array of differences for array elements" do
        yaml1 = <<~YAML
          - 1
          - 2
          - 3
        YAML
        yaml2 = <<~YAML
          - 1
          - 9
          - 3
        YAML

        result = described_class.equivalent?(yaml1, yaml2, verbose: true)
        expect(result).to be_an(Array)
        expect(result).not_to be_empty
        expect(result.first[:path]).to eq("[1]")
        expect(result.first[:value1]).to eq(2)
        expect(result.first[:value2]).to eq(9)
      end

      it "returns array of differences for nested structures" do
        yaml1 = <<~YAML
          outer:
            inner: 1
        YAML
        yaml2 = <<~YAML
          outer:
            inner: 2
        YAML

        result = described_class.equivalent?(yaml1, yaml2, verbose: true)
        expect(result).to be_an(Array)
        expect(result).not_to be_empty
        expect(result.first[:path]).to eq("outer.inner")
      end
    end

    context "with options" do
      it "respects ignore_attr_order option" do
        yaml1 = <<~YAML
          b: 2
          a: 1
          c: 3
        YAML
        yaml2 = <<~YAML
          a: 1
          c: 3
          b: 2
        YAML

        expect(described_class.equivalent?(yaml1, yaml2, ignore_attr_order: true)).to be true
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
        yaml1 = "key: value"
        obj2 = { "key" => "value" }

        expect(described_class.equivalent?(yaml1, obj2)).to be true
      end
    end

    context "with complex nested structures" do
      it "compares deeply nested structures" do
        yaml1 = <<~YAML
          level1:
            level2:
              level3:
                value: 42
        YAML
        yaml2 = <<~YAML
          level1:
            level2:
              level3:
                value: 42
        YAML

        expect(described_class.equivalent?(yaml1, yaml2)).to be true
      end

      it "detects differences in deeply nested structures" do
        yaml1 = <<~YAML
          level1:
            level2:
              level3:
                value: 42
        YAML
        yaml2 = <<~YAML
          level1:
            level2:
              level3:
                value: 43
        YAML

        expect(described_class.equivalent?(yaml1, yaml2)).to be false
      end

      it "handles arrays of complex objects" do
        yaml1 = <<~YAML
          - a: 1
            b:
              - 1
              - 2
          - c: 3
        YAML
        yaml2 = <<~YAML
          - a: 1
            b:
              - 1
              - 2
          - c: 3
        YAML

        expect(described_class.equivalent?(yaml1, yaml2)).to be true
      end
    end

    context "delegation to JsonComparator" do
      it "delegates Ruby object comparison to JsonComparator" do
        yaml1 = "key: value"
        yaml2 = "key: value"

        # Verify it uses JsonComparator's logic
        expect(Canon::Comparison::JsonComparator).to receive(:send).with(
          :compare_ruby_objects,
          { "key" => "value" },
          { "key" => "value" },
          hash_including(ignore_attr_order: true),
          [],
          ""
        ).and_call_original

        described_class.equivalent?(yaml1, yaml2)
      end
    end
  end
end
