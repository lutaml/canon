# frozen_string_literal: true

require "spec_helper"
require "canon/diff_formatter"
require "canon/comparison/comparison_result"

RSpec.describe Canon::DiffFormatter, "#format_original_strings" do
  describe "original input strings display" do
    let(:xml1) do
      <<~XML
        <root>
          <element>value1</element>
        </root>
      XML
    end

    let(:xml2) do
      <<~XML
        <root>
          <element>value2</element>
        </root>
      XML
    end

    context "when verbose_diff is enabled" do
      it "displays original input strings in RSpec style" do
        formatter = described_class.new(
          use_color: false,
          verbose_diff: true,
        )

        comparison_result = Canon::Comparison::ComparisonResult.new(
          differences: [],
          preprocessed_strings: [xml1, xml2],
          original_strings: [xml1, xml2],
          format: :xml,
          match_options: {},
        )

        output = formatter.format_comparison_result(comparison_result, xml1, xml2)

        expect(output).to include("ORIGINAL INPUT STRINGS")
        expect(output).to include("Expected (as string):")
        expect(output).to include("Actual (as string):")
        expect(output).to include("<root>")
        expect(output).to include("<element>value1</element>")
        expect(output).to include("<element>value2</element>")
      end

      it "shows line numbers for each line" do
        formatter = described_class.new(
          use_color: false,
          verbose_diff: true,
        )

        comparison_result = Canon::Comparison::ComparisonResult.new(
          differences: [],
          preprocessed_strings: [xml1, xml2],
          original_strings: [xml1, xml2],
          format: :xml,
          match_options: {},
        )

        output = formatter.format_comparison_result(comparison_result, xml1, xml2)

        # Check for line numbers
        expect(output).to match(/\s+1\s+\|/)
        expect(output).to match(/\s+2\s+\|/)
        expect(output).to match(/\s+3\s+\|/)
      end
    end

    context "when verbose_diff is disabled" do
      it "does not display original input strings" do
        formatter = described_class.new(
          use_color: false,
          verbose_diff: false,
        )

        comparison_result = Canon::Comparison::ComparisonResult.new(
          differences: [],
          preprocessed_strings: [xml1, xml2],
          original_strings: [xml1, xml2],
          format: :xml,
          match_options: {},
        )

        output = formatter.format_comparison_result(comparison_result, xml1, xml2)

        expect(output).not_to include("ORIGINAL INPUT STRINGS")
        expect(output).not_to include("Expected (as string):")
        expect(output).not_to include("Actual (as string):")
      end
    end

    context "with multiline content" do
      let(:json1) do
        <<~JSON
          {
            "key1": "value1",
            "key2": "value2"
          }
        JSON
      end

      let(:json2) do
        <<~JSON
          {
            "key1": "value1",
            "key2": "different"
          }
        JSON
      end

      it "displays all lines with proper formatting" do
        formatter = described_class.new(
          use_color: false,
          verbose_diff: true,
        )

        comparison_result = Canon::Comparison::ComparisonResult.new(
          differences: [],
          preprocessed_strings: [json1, json2],
          original_strings: [json1, json2],
          format: :json,
          match_options: {},
        )

        output = formatter.format_comparison_result(comparison_result, json1, json2)

        expect(output).to include("ORIGINAL INPUT STRINGS")
        expect(output).to include('"key1": "value1"')
        expect(output).to include('"key2": "value2"')
        expect(output).to include('"key2": "different"')
      end
    end
  end
end