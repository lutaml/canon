# frozen_string_literal: true

require "spec_helper"
require "canon/comparison/xml_comparator"

RSpec.describe Canon::Comparison::XmlComparator,
               "multiple differences capture" do
  describe "positional children comparison" do
    context "with multiple differing comment children" do
      let(:xml1) do
        <<~XML
          <root>
            <!-- Comment 1 -->
            <item>A</item>
            <!-- Comment 2 -->
            <item>B</item>
            <!-- Comment 3 -->
            <item>C</item>
          </root>
        XML
      end

      let(:xml2) do
        <<~XML
          <root>
            <!-- Different 1 -->
            <item>A</item>
            <!-- Different 2 -->
            <item>B</item>
            <!-- Different 3 -->
            <item>C</item>
          </root>
        XML
      end

      it "captures ALL comment differences, not just the first one" do
        result = described_class.equivalent?(xml1, xml2, verbose: true,
                                                         comments: :strict)

        expect(result).to be_a(Canon::Comparison::ComparisonResult)
        expect(result.equivalent?).to be false

        # Should have 3 comment differences, not 1
        comment_diffs = result.differences.select do |diff|
          diff.dimension == :comments
        end

        expect(comment_diffs.length).to eq(3)
      end

      it "continues comparing all children after finding first difference" do
        result = described_class.equivalent?(xml1, xml2, verbose: true,
                                                         comments: :strict)

        # Verify we got differences for all 3 comment pairs
        comment_diffs = result.differences.select do |diff|
          diff.dimension == :comments
        end

        # Extract comment values
        comment_values = comment_diffs.map do |diff|
          [diff.node1.value.strip, diff.node2.value.strip]
        end

        expect(comment_values).to contain_exactly(
          ["Comment 1", "Different 1"],
          ["Comment 2", "Different 2"],
          ["Comment 3", "Different 3"],
        )
      end
    end

    context "with multiple differing text nodes" do
      let(:xml1) { "<root><a>X</a><b>Y</b><c>Z</c></root>" }
      let(:xml2) { "<root><a>1</a><b>2</b><c>3</c></root>" }

      it "captures all text content differences" do
        result = described_class.equivalent?(xml1, xml2, verbose: true,
                                                         text_content: :strict)

        text_diffs = result.differences.select do |diff|
          diff.dimension == :text_content
        end

        # Should have 3 text differences
        expect(text_diffs.length).to eq(3)
      end
    end
  end
end
