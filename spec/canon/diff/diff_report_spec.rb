# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Diff::DiffReport do
  let(:block1) { Canon::Diff::DiffBlock.new(start_idx: 5, end_idx: 7, types: ["-"]) }
  let(:block2) { Canon::Diff::DiffBlock.new(start_idx: 12, end_idx: 15, types: ["+"]) }
  let(:context1) { Canon::Diff::DiffContext.new(start_idx: 3, end_idx: 20, blocks: [block1, block2]) }
  let(:context2) { Canon::Diff::DiffContext.new(start_idx: 30, end_idx: 40, blocks: [block1]) }

  describe "#initialize" do
    it "creates a report with element name and file names" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1, context2],
      )

      expect(report.element_name).to eq("root")
      expect(report.file1_name).to eq("file1.xml")
      expect(report.file2_name).to eq("file2.xml")
      expect(report.contexts).to eq([context1, context2])
    end

    it "accepts a single context" do
      report = described_class.new(
        element_name: "section",
        file1_name: "a.xml",
        file2_name: "b.xml",
        contexts: [context1],
      )

      expect(report.contexts).to eq([context1])
    end

    it "defaults to empty contexts array" do
      report = described_class.new(
        element_name: "div",
        file1_name: "x.html",
        file2_name: "y.html",
      )

      expect(report.contexts).to eq([])
    end

    it "handles reports with no element name" do
      report = described_class.new(
        element_name: nil,
        file1_name: "file1.json",
        file2_name: "file2.json",
        contexts: [],
      )

      expect(report.element_name).to be_nil
    end
  end

  describe "#add_context" do
    it "adds a context to the report" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
      )

      report.add_context(context1)

      expect(report.contexts).to eq([context1])
    end

    it "appends contexts in order" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
      )

      report.add_context(context1)
      report.add_context(context2)

      expect(report.contexts).to eq([context1, context2])
    end

    it "allows adding multiple contexts" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
      )

      5.times do |i|
        ctx = Canon::Diff::DiffContext.new(start_idx: i * 10,
                                           end_idx: i * 10 + 5, blocks: [])
        report.add_context(ctx)
      end

      expect(report.contexts.length).to eq(5)
    end
  end

  describe "#context_count" do
    it "returns the number of contexts" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1, context2],
      )

      expect(report.context_count).to eq(2)
    end

    it "returns 0 for reports with no contexts" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
      )

      expect(report.context_count).to eq(0)
    end

    it "updates after adding contexts" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
      )

      expect(report.context_count).to eq(0)

      report.add_context(context1)
      expect(report.context_count).to eq(1)

      report.add_context(context2)
      expect(report.context_count).to eq(2)
    end
  end

  describe "#block_count" do
    it "returns the total number of blocks across all contexts" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1, context2],
      )

      # context1 has 2 blocks, context2 has 1 block
      expect(report.block_count).to eq(3)
    end

    it "returns 0 for reports with no contexts" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
      )

      expect(report.block_count).to eq(0)
    end

    it "returns 0 for contexts with no blocks" do
      empty_context = Canon::Diff::DiffContext.new(start_idx: 0, end_idx: 10,
                                                   blocks: [])
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [empty_context],
      )

      expect(report.block_count).to eq(0)
    end
  end

  describe "#change_count" do
    it "returns the total number of changed lines across all blocks" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1, context2],
      )

      # context1: block1 (5-7 = 3 lines) + block2 (12-15 = 4 lines) = 7
      # context2: block1 (5-7 = 3 lines) = 3
      # Total = 10
      expect(report.change_count).to eq(10)
    end

    it "returns 0 for reports with no blocks" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
      )

      expect(report.change_count).to eq(0)
    end

    it "counts lines from all blocks" do
      single_line_block = Canon::Diff::DiffBlock.new(start_idx: 10,
                                                     end_idx: 10, types: ["-"])
      multi_line_block = Canon::Diff::DiffBlock.new(start_idx: 20, end_idx: 25,
                                                    types: ["+"])
      ctx = Canon::Diff::DiffContext.new(start_idx: 0, end_idx: 30,
                                         blocks: [single_line_block, multi_line_block])

      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [ctx],
      )

      # 1 line + 6 lines = 7 lines
      expect(report.change_count).to eq(7)
    end
  end

  describe "#has_differences?" do
    it "returns true when report has contexts" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1],
      )

      expect(report.has_differences?).to be true
    end

    it "returns false when report has no contexts" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
      )

      expect(report.has_differences?).to be false
    end

    it "returns true even if contexts have no blocks" do
      empty_context = Canon::Diff::DiffContext.new(start_idx: 0, end_idx: 10,
                                                   blocks: [])
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [empty_context],
      )

      expect(report.has_differences?).to be true
    end
  end

  describe "#includes_type?" do
    it "returns true when any block contains the specified type" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1, context2],
      )

      expect(report.includes_type?("-")).to be true
      expect(report.includes_type?("+")).to be true
    end

    it "returns false when no blocks contain the specified type" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1, context2],
      )

      expect(report.includes_type?("!")).to be false
    end

    it "returns false for empty reports" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
      )

      expect(report.includes_type?("-")).to be false
    end
  end

  describe "#contexts_with_type" do
    it "returns contexts that contain the specified type" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1, context2],
      )

      # Both contexts have blocks with "-" type
      result = report.contexts_with_type("-")
      expect(result).to contain_exactly(context1, context2)
    end

    it "returns only contexts with the specified type" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1, context2],
      )

      # Only context1 has blocks with "+" type
      result = report.contexts_with_type("+")
      expect(result).to eq([context1])
    end

    it "returns empty array when no contexts have the type" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1, context2],
      )

      result = report.contexts_with_type("!")
      expect(result).to be_empty
    end

    it "returns empty array for reports with no contexts" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
      )

      result = report.contexts_with_type("-")
      expect(result).to be_empty
    end
  end

  describe "#summary" do
    it "returns a hash with statistics" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1, context2],
      )

      summary = report.summary

      expect(summary).to be_a(Hash)
      expect(summary[:contexts]).to eq(2)
      expect(summary[:blocks]).to eq(3)
      expect(summary[:changes]).to eq(10)
    end

    it "returns correct counts for single context" do
      report = described_class.new(
        element_name: "section",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1],
      )

      summary = report.summary

      expect(summary[:contexts]).to eq(1)
      expect(summary[:blocks]).to eq(2)
      expect(summary[:changes]).to eq(7)
    end

    it "returns zeros for reports with no differences" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
      )

      summary = report.summary

      expect(summary[:contexts]).to eq(0)
      expect(summary[:blocks]).to eq(0)
      expect(summary[:changes]).to eq(0)
    end
  end

  describe "#to_h" do
    it "returns a hash representation of the report" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1, context2],
      )

      result = report.to_h

      expect(result).to eq({
                             element_name: "root",
                             file1_name: "file1.xml",
                             file2_name: "file2.xml",
                             contexts: [context1.to_h, context2.to_h],
                             summary: {
                               contexts: 2,
                               blocks: 3,
                               changes: 10,
                             },
                           })
    end

    it "includes empty contexts array" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
      )

      result = report.to_h

      expect(result[:contexts]).to eq([])
    end

    it "converts all contexts to hashes" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1, context2],
      )

      result = report.to_h

      expect(result[:contexts]).to all(be_a(Hash))
      expect(result[:contexts].length).to eq(2)
    end
  end

  describe "#==" do
    it "returns true for identical reports" do
      report1 = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1],
      )
      report2 = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1],
      )

      expect(report1).to eq(report2)
    end

    it "returns false for different element names" do
      report1 = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1],
      )
      report2 = described_class.new(
        element_name: "section",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1],
      )

      expect(report1).not_to eq(report2)
    end

    it "returns false for different file names" do
      report1 = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1],
      )
      report2 = described_class.new(
        element_name: "root",
        file1_name: "different.xml",
        file2_name: "file2.xml",
        contexts: [context1],
      )

      expect(report1).not_to eq(report2)
    end

    it "returns false for different contexts" do
      report1 = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1],
      )
      report2 = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context2],
      )

      expect(report1).not_to eq(report2)
    end

    it "returns false when comparing to non-DiffReport objects" do
      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [context1],
      )

      expect(report).not_to eq("not a report")
      expect(report).not_to be_nil
      expect(report).not_to eq({ element_name: "root", contexts: [context1] })
    end
  end

  describe "edge cases" do
    it "handles many contexts" do
      many_contexts = Array.new(100) do |i|
        Canon::Diff::DiffContext.new(start_idx: i * 10, end_idx: i * 10 + 5,
                                     blocks: [])
      end

      report = described_class.new(
        element_name: "root",
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: many_contexts,
      )

      expect(report.context_count).to eq(100)
    end

    it "handles very long file names" do
      long_name = "#{'a' * 1000}.xml"

      report = described_class.new(
        element_name: "root",
        file1_name: long_name,
        file2_name: long_name,
        contexts: [],
      )

      expect(report.file1_name).to eq(long_name)
    end

    it "handles nil element names" do
      report = described_class.new(
        element_name: nil,
        file1_name: "file1.xml",
        file2_name: "file2.xml",
        contexts: [],
      )

      expect(report.element_name).to be_nil
      expect(report.summary).not_to be_nil
    end
  end
end
