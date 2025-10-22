# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Diff::DiffBlockBuilder do
  let(:diff_node_normative) do
    Canon::Diff::DiffNode.new(
      node1: "old text",
      node2: "new text",
      dimension: :text_content,
      reason: "Text content differs",
    ).tap { |node| node.normative = true }
  end

  let(:diff_node_informative) do
    Canon::Diff::DiffNode.new(
      node1: "<div a='1' b='2'>",
      node2: "<div b='2' a='1'>",
      dimension: :attribute_order,
      reason: "Attribute order differs",
    ).tap { |node| node.normative = false }
  end

  describe ".build_blocks" do
    context "with contiguous changed lines" do
      it "groups them into a single block" do
        diff_lines = [
          Canon::Diff::DiffLine.new(line_number: 0, type: :unchanged,
                                    content: "line 1"),
          Canon::Diff::DiffLine.new(line_number: 1, type: :removed,
                                    content: "old line 2", diff_node: diff_node_normative),
          Canon::Diff::DiffLine.new(line_number: 2, type: :added,
                                    content: "new line 2", diff_node: diff_node_normative),
          Canon::Diff::DiffLine.new(line_number: 3, type: :removed,
                                    content: "old line 3", diff_node: diff_node_normative),
          Canon::Diff::DiffLine.new(line_number: 4, type: :unchanged,
                                    content: "line 4"),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks.length).to eq(1)
        expect(blocks[0].start_idx).to eq(1)
        expect(blocks[0].end_idx).to eq(3)
        expect(blocks[0].diff_lines.length).to eq(3)
      end
    end

    context "with non-contiguous changed lines" do
      it "creates separate blocks" do
        diff_lines = [
          Canon::Diff::DiffLine.new(line_number: 0, type: :removed,
                                    content: "old line 1", diff_node: diff_node_normative),
          Canon::Diff::DiffLine.new(line_number: 1, type: :unchanged,
                                    content: "line 2"),
          Canon::Diff::DiffLine.new(line_number: 2, type: :unchanged,
                                    content: "line 3"),
          Canon::Diff::DiffLine.new(line_number: 3, type: :added,
                                    content: "new line 4", diff_node: diff_node_normative),
          Canon::Diff::DiffLine.new(line_number: 4, type: :unchanged,
                                    content: "line 5"),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks.length).to eq(2)
        expect(blocks[0].start_idx).to eq(0)
        expect(blocks[0].end_idx).to eq(0)
        expect(blocks[1].start_idx).to eq(3)
        expect(blocks[1].end_idx).to eq(3)
      end
    end

    context "with only unchanged lines" do
      it "returns empty array" do
        diff_lines = [
          Canon::Diff::DiffLine.new(line_number: 0, type: :unchanged,
                                    content: "line 1"),
          Canon::Diff::DiffLine.new(line_number: 1, type: :unchanged,
                                    content: "line 2"),
          Canon::Diff::DiffLine.new(line_number: 2, type: :unchanged,
                                    content: "line 3"),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks).to be_empty
      end
    end

    context "with block types" do
      it "sets types based on contained line types" do
        diff_lines = [
          Canon::Diff::DiffLine.new(line_number: 0, type: :removed,
                                    content: "old", diff_node: diff_node_normative),
          Canon::Diff::DiffLine.new(line_number: 1, type: :added,
                                    content: "new", diff_node: diff_node_normative),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks[0].types).to contain_exactly("-", "+")
      end

      it "handles changed type" do
        diff_lines = [
          Canon::Diff::DiffLine.new(line_number: 0, type: :changed,
                                    content: "modified", diff_node: diff_node_normative),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks[0].types).to contain_exactly("!")
      end
    end
  end

  describe "normative/informative determination" do
    context "with all normative diff lines" do
      it "marks block as normative" do
        diff_lines = [
          Canon::Diff::DiffLine.new(
            line_number: 0,
            type: :removed,
            content: "old",
            diff_node: diff_node_normative,
          ),
          Canon::Diff::DiffLine.new(
            line_number: 1,
            type: :added,
            content: "new",
            diff_node: diff_node_normative,
          ),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks[0]).to be_normative
        expect(blocks[0]).not_to be_informative
      end
    end

    context "with all informative diff lines" do
      it "marks block as informative" do
        diff_lines = [
          Canon::Diff::DiffLine.new(
            line_number: 0,
            type: :removed,
            content: "old",
            diff_node: diff_node_informative,
          ),
          Canon::Diff::DiffLine.new(
            line_number: 1,
            type: :added,
            content: "new",
            diff_node: diff_node_informative,
          ),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks[0]).to be_informative
        expect(blocks[0]).not_to be_normative
      end
    end

    context "with mixed normative and informative diff lines" do
      it "marks block as normative if ANY line is normative" do
        diff_lines = [
          Canon::Diff::DiffLine.new(
            line_number: 0,
            type: :removed,
            content: "old",
            diff_node: diff_node_informative,
          ),
          Canon::Diff::DiffLine.new(
            line_number: 1,
            type: :added,
            content: "new",
            diff_node: diff_node_normative,
          ),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks[0]).to be_normative
        expect(blocks[0]).not_to be_informative
      end
    end
  end

  describe "filtering by show_diffs" do
    let(:normative_line) do
      Canon::Diff::DiffLine.new(
        line_number: 0,
        type: :removed,
        content: "normative",
        diff_node: diff_node_normative,
      )
    end

    let(:innormative_line) do
      Canon::Diff::DiffLine.new(
        line_number: 1,
        type: :removed,
        content: "informative",
        diff_node: diff_node_informative,
      )
    end

    context "with show_diffs: :normative" do
      it "returns only normative blocks" do
        diff_lines = [
          normative_line,
          Canon::Diff::DiffLine.new(line_number: 2, type: :unchanged,
                                    content: "unchanged"),
          innormative_line,
        ]

        blocks = described_class.build_blocks(diff_lines,
                                              show_diffs: :normative)

        expect(blocks.length).to eq(1)
        expect(blocks[0]).to be_normative
      end

      it "filters out informative blocks" do
        diff_lines = [innormative_line]

        blocks = described_class.build_blocks(diff_lines,
                                              show_diffs: :normative)

        expect(blocks).to be_empty
      end
    end

    context "with show_diffs: :informative" do
      it "returns only informative blocks" do
        diff_lines = [
          normative_line,
          Canon::Diff::DiffLine.new(line_number: 2, type: :unchanged,
                                    content: "unchanged"),
          innormative_line,
        ]

        blocks = described_class.build_blocks(diff_lines,
                                              show_diffs: :informative)

        expect(blocks.length).to eq(1)
        expect(blocks[0]).to be_informative
      end

      it "filters out normative blocks" do
        diff_lines = [normative_line]

        blocks = described_class.build_blocks(diff_lines,
                                              show_diffs: :informative)

        expect(blocks).to be_empty
      end
    end

    context "with show_diffs: :all" do
      it "returns all blocks" do
        diff_lines = [
          normative_line,
          Canon::Diff::DiffLine.new(line_number: 2, type: :unchanged,
                                    content: "unchanged"),
          innormative_line,
        ]

        blocks = described_class.build_blocks(diff_lines, show_diffs: :all)

        expect(blocks.length).to eq(2)
        expect(blocks[0]).to be_normative
        expect(blocks[1]).to be_informative
      end
    end

    context "with default (no show_diffs specified)" do
      it "returns all blocks" do
        diff_lines = [
          normative_line,
          Canon::Diff::DiffLine.new(line_number: 2, type: :unchanged,
                                    content: "unchanged"),
          innormative_line,
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks.length).to eq(2)
      end
    end
  end

  describe "edge cases" do
    context "with empty diff_lines array" do
      it "returns empty array" do
        blocks = described_class.build_blocks([])

        expect(blocks).to be_empty
      end
    end

    context "with single changed line" do
      it "creates a single-line block" do
        diff_lines = [
          Canon::Diff::DiffLine.new(
            line_number: 0,
            type: :removed,
            content: "only line",
            diff_node: diff_node_normative,
          ),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks.length).to eq(1)
        expect(blocks[0].start_idx).to eq(0)
        expect(blocks[0].end_idx).to eq(0)
        expect(blocks[0].diff_lines.length).to eq(1)
      end
    end

    context "with block at end of file" do
      it "correctly sets end_idx" do
        diff_lines = [
          Canon::Diff::DiffLine.new(line_number: 0, type: :unchanged,
                                    content: "line 1"),
          Canon::Diff::DiffLine.new(line_number: 1, type: :unchanged,
                                    content: "line 2"),
          Canon::Diff::DiffLine.new(
            line_number: 2,
            type: :removed,
            content: "last line",
            diff_node: diff_node_normative,
          ),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks.length).to eq(1)
        expect(blocks[0].start_idx).to eq(2)
        expect(blocks[0].end_idx).to eq(2)
      end
    end

    context "with block at start of file" do
      it "correctly sets start_idx to 0" do
        diff_lines = [
          Canon::Diff::DiffLine.new(
            line_number: 0,
            type: :removed,
            content: "first line",
            diff_node: diff_node_normative,
          ),
          Canon::Diff::DiffLine.new(line_number: 1, type: :unchanged,
                                    content: "line 2"),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks.length).to eq(1)
        expect(blocks[0].start_idx).to eq(0)
        expect(blocks[0].end_idx).to eq(0)
      end
    end

    context "with all changed lines" do
      it "creates one big block" do
        diff_lines = [
          Canon::Diff::DiffLine.new(line_number: 0, type: :removed,
                                    content: "line 1", diff_node: diff_node_normative),
          Canon::Diff::DiffLine.new(line_number: 1, type: :added,
                                    content: "line 2", diff_node: diff_node_normative),
          Canon::Diff::DiffLine.new(line_number: 2, type: :changed,
                                    content: "line 3", diff_node: diff_node_normative),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks.length).to eq(1)
        expect(blocks[0].start_idx).to eq(0)
        expect(blocks[0].end_idx).to eq(2)
        expect(blocks[0].diff_lines.length).to eq(3)
      end
    end

    context "with multiple separate single-line blocks" do
      it "creates multiple blocks" do
        diff_lines = [
          Canon::Diff::DiffLine.new(line_number: 0, type: :removed,
                                    content: "line 1", diff_node: diff_node_normative),
          Canon::Diff::DiffLine.new(line_number: 1, type: :unchanged,
                                    content: "line 2"),
          Canon::Diff::DiffLine.new(line_number: 2, type: :removed,
                                    content: "line 3", diff_node: diff_node_normative),
          Canon::Diff::DiffLine.new(line_number: 3, type: :unchanged,
                                    content: "line 4"),
          Canon::Diff::DiffLine.new(line_number: 4, type: :removed,
                                    content: "line 5", diff_node: diff_node_normative),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks.length).to eq(3)
        expect(blocks[0].diff_lines.length).to eq(1)
        expect(blocks[1].diff_lines.length).to eq(1)
        expect(blocks[2].diff_lines.length).to eq(1)
      end
    end
  end

  describe "complex scenarios" do
    context "with mixed normative/informative blocks" do
      it "correctly filters and preserves block identity" do
        diff_lines = [
          Canon::Diff::DiffLine.new(line_number: 0, type: :removed,
                                    content: "normative 1", diff_node: diff_node_normative),
          Canon::Diff::DiffLine.new(line_number: 1, type: :unchanged,
                                    content: "unchanged"),
          Canon::Diff::DiffLine.new(line_number: 2, type: :removed,
                                    content: "informative 1", diff_node: diff_node_informative),
          Canon::Diff::DiffLine.new(line_number: 3, type: :unchanged,
                                    content: "unchanged"),
          Canon::Diff::DiffLine.new(line_number: 4, type: :removed,
                                    content: "normative 2", diff_node: diff_node_normative),
        ]

        all_blocks = described_class.build_blocks(diff_lines, show_diffs: :all)
        normative_blocks = described_class.build_blocks(diff_lines,
                                                        show_diffs: :normative)
        innormative_blocks = described_class.build_blocks(diff_lines,
                                                          show_diffs: :informative)

        expect(all_blocks.length).to eq(3)
        expect(normative_blocks.length).to eq(2)
        expect(innormative_blocks.length).to eq(1)

        expect(normative_blocks[0].start_idx).to eq(0)
        expect(normative_blocks[1].start_idx).to eq(4)
        expect(innormative_blocks[0].start_idx).to eq(2)
      end
    end

    context "with block containing multiple line types" do
      it "includes all types in the block" do
        diff_lines = [
          Canon::Diff::DiffLine.new(line_number: 0, type: :removed,
                                    content: "old", diff_node: diff_node_normative),
          Canon::Diff::DiffLine.new(line_number: 1, type: :added,
                                    content: "new", diff_node: diff_node_normative),
          Canon::Diff::DiffLine.new(line_number: 2, type: :changed,
                                    content: "mod", diff_node: diff_node_normative),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks[0].types).to contain_exactly("-", "+", "!")
      end
    end

    context "with long contiguous block" do
      it "groups all lines into single block" do
        diff_lines = Array.new(100) do |i|
          Canon::Diff::DiffLine.new(
            line_number: i,
            type: :removed,
            content: "line #{i}",
            diff_node: diff_node_normative,
          )
        end

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks.length).to eq(1)
        expect(blocks[0].diff_lines.length).to eq(100)
        expect(blocks[0].start_idx).to eq(0)
        expect(blocks[0].end_idx).to eq(99)
      end
    end
  end
end
