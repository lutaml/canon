# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Diff::DiffBlockBuilder do
  let(:diff_node_active) do
    Canon::Diff::DiffNode.new(
      node1: "old text",
      node2: "new text",
      dimension: :text_content,
      reason: "Text content differs",
    ).tap { |node| node.active = true }
  end

  let(:diff_node_inactive) do
    Canon::Diff::DiffNode.new(
      node1: "<div a='1' b='2'>",
      node2: "<div b='2' a='1'>",
      dimension: :attribute_order,
      reason: "Attribute order differs",
    ).tap { |node| node.active = false }
  end

  describe ".build_blocks" do
    context "with contiguous changed lines" do
      it "groups them into a single block" do
        diff_lines = [
          Canon::Diff::DiffLine.new(line_number: 0, type: :unchanged, content: "line 1"),
          Canon::Diff::DiffLine.new(line_number: 1, type: :removed, content: "old line 2", diff_node: diff_node_active),
          Canon::Diff::DiffLine.new(line_number: 2, type: :added, content: "new line 2", diff_node: diff_node_active),
          Canon::Diff::DiffLine.new(line_number: 3, type: :removed, content: "old line 3", diff_node: diff_node_active),
          Canon::Diff::DiffLine.new(line_number: 4, type: :unchanged, content: "line 4"),
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
          Canon::Diff::DiffLine.new(line_number: 0, type: :removed, content: "old line 1", diff_node: diff_node_active),
          Canon::Diff::DiffLine.new(line_number: 1, type: :unchanged, content: "line 2"),
          Canon::Diff::DiffLine.new(line_number: 2, type: :unchanged, content: "line 3"),
          Canon::Diff::DiffLine.new(line_number: 3, type: :added, content: "new line 4", diff_node: diff_node_active),
          Canon::Diff::DiffLine.new(line_number: 4, type: :unchanged, content: "line 5"),
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
          Canon::Diff::DiffLine.new(line_number: 0, type: :unchanged, content: "line 1"),
          Canon::Diff::DiffLine.new(line_number: 1, type: :unchanged, content: "line 2"),
          Canon::Diff::DiffLine.new(line_number: 2, type: :unchanged, content: "line 3"),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks).to be_empty
      end
    end

    context "with block types" do
      it "sets types based on contained line types" do
        diff_lines = [
          Canon::Diff::DiffLine.new(line_number: 0, type: :removed, content: "old", diff_node: diff_node_active),
          Canon::Diff::DiffLine.new(line_number: 1, type: :added, content: "new", diff_node: diff_node_active),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks[0].types).to contain_exactly("-", "+")
      end

      it "handles changed type" do
        diff_lines = [
          Canon::Diff::DiffLine.new(line_number: 0, type: :changed, content: "modified", diff_node: diff_node_active),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks[0].types).to contain_exactly("!")
      end
    end
  end

  describe "active/inactive determination" do
    context "with all active diff lines" do
      it "marks block as active" do
        diff_lines = [
          Canon::Diff::DiffLine.new(
            line_number: 0,
            type: :removed,
            content: "old",
            diff_node: diff_node_active,
          ),
          Canon::Diff::DiffLine.new(
            line_number: 1,
            type: :added,
            content: "new",
            diff_node: diff_node_active,
          ),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks[0]).to be_active
        expect(blocks[0]).not_to be_inactive
      end
    end

    context "with all inactive diff lines" do
      it "marks block as inactive" do
        diff_lines = [
          Canon::Diff::DiffLine.new(
            line_number: 0,
            type: :removed,
            content: "old",
            diff_node: diff_node_inactive,
          ),
          Canon::Diff::DiffLine.new(
            line_number: 1,
            type: :added,
            content: "new",
            diff_node: diff_node_inactive,
          ),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks[0]).to be_inactive
        expect(blocks[0]).not_to be_active
      end
    end

    context "with mixed active and inactive diff lines" do
      it "marks block as active if ANY line is active" do
        diff_lines = [
          Canon::Diff::DiffLine.new(
            line_number: 0,
            type: :removed,
            content: "old",
            diff_node: diff_node_inactive,
          ),
          Canon::Diff::DiffLine.new(
            line_number: 1,
            type: :added,
            content: "new",
            diff_node: diff_node_active,
          ),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks[0]).to be_active
        expect(blocks[0]).not_to be_inactive
      end
    end
  end

  describe "filtering by show_diffs" do
    let(:active_line) do
      Canon::Diff::DiffLine.new(
        line_number: 0,
        type: :removed,
        content: "active",
        diff_node: diff_node_active,
      )
    end

    let(:inactive_line) do
      Canon::Diff::DiffLine.new(
        line_number: 1,
        type: :removed,
        content: "inactive",
        diff_node: diff_node_inactive,
      )
    end

    context "with show_diffs: :active" do
      it "returns only active blocks" do
        diff_lines = [
          active_line,
          Canon::Diff::DiffLine.new(line_number: 2, type: :unchanged, content: "unchanged"),
          inactive_line,
        ]

        blocks = described_class.build_blocks(diff_lines, show_diffs: :active)

        expect(blocks.length).to eq(1)
        expect(blocks[0]).to be_active
      end

      it "filters out inactive blocks" do
        diff_lines = [inactive_line]

        blocks = described_class.build_blocks(diff_lines, show_diffs: :active)

        expect(blocks).to be_empty
      end
    end

    context "with show_diffs: :inactive" do
      it "returns only inactive blocks" do
        diff_lines = [
          active_line,
          Canon::Diff::DiffLine.new(line_number: 2, type: :unchanged, content: "unchanged"),
          inactive_line,
        ]

        blocks = described_class.build_blocks(diff_lines, show_diffs: :inactive)

        expect(blocks.length).to eq(1)
        expect(blocks[0]).to be_inactive
      end

      it "filters out active blocks" do
        diff_lines = [active_line]

        blocks = described_class.build_blocks(diff_lines, show_diffs: :inactive)

        expect(blocks).to be_empty
      end
    end

    context "with show_diffs: :all" do
      it "returns all blocks" do
        diff_lines = [
          active_line,
          Canon::Diff::DiffLine.new(line_number: 2, type: :unchanged, content: "unchanged"),
          inactive_line,
        ]

        blocks = described_class.build_blocks(diff_lines, show_diffs: :all)

        expect(blocks.length).to eq(2)
        expect(blocks[0]).to be_active
        expect(blocks[1]).to be_inactive
      end
    end

    context "with default (no show_diffs specified)" do
      it "returns all blocks" do
        diff_lines = [
          active_line,
          Canon::Diff::DiffLine.new(line_number: 2, type: :unchanged, content: "unchanged"),
          inactive_line,
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
            diff_node: diff_node_active,
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
          Canon::Diff::DiffLine.new(line_number: 0, type: :unchanged, content: "line 1"),
          Canon::Diff::DiffLine.new(line_number: 1, type: :unchanged, content: "line 2"),
          Canon::Diff::DiffLine.new(
            line_number: 2,
            type: :removed,
            content: "last line",
            diff_node: diff_node_active,
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
            diff_node: diff_node_active,
          ),
          Canon::Diff::DiffLine.new(line_number: 1, type: :unchanged, content: "line 2"),
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
          Canon::Diff::DiffLine.new(line_number: 0, type: :removed, content: "line 1", diff_node: diff_node_active),
          Canon::Diff::DiffLine.new(line_number: 1, type: :added, content: "line 2", diff_node: diff_node_active),
          Canon::Diff::DiffLine.new(line_number: 2, type: :changed, content: "line 3", diff_node: diff_node_active),
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
          Canon::Diff::DiffLine.new(line_number: 0, type: :removed, content: "line 1", diff_node: diff_node_active),
          Canon::Diff::DiffLine.new(line_number: 1, type: :unchanged, content: "line 2"),
          Canon::Diff::DiffLine.new(line_number: 2, type: :removed, content: "line 3", diff_node: diff_node_active),
          Canon::Diff::DiffLine.new(line_number: 3, type: :unchanged, content: "line 4"),
          Canon::Diff::DiffLine.new(line_number: 4, type: :removed, content: "line 5", diff_node: diff_node_active),
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
    context "with mixed active/inactive blocks" do
      it "correctly filters and preserves block identity" do
        diff_lines = [
          Canon::Diff::DiffLine.new(line_number: 0, type: :removed, content: "active 1", diff_node: diff_node_active),
          Canon::Diff::DiffLine.new(line_number: 1, type: :unchanged, content: "unchanged"),
          Canon::Diff::DiffLine.new(line_number: 2, type: :removed, content: "inactive 1", diff_node: diff_node_inactive),
          Canon::Diff::DiffLine.new(line_number: 3, type: :unchanged, content: "unchanged"),
          Canon::Diff::DiffLine.new(line_number: 4, type: :removed, content: "active 2", diff_node: diff_node_active),
        ]

        all_blocks = described_class.build_blocks(diff_lines, show_diffs: :all)
        active_blocks = described_class.build_blocks(diff_lines, show_diffs: :active)
        inactive_blocks = described_class.build_blocks(diff_lines, show_diffs: :inactive)

        expect(all_blocks.length).to eq(3)
        expect(active_blocks.length).to eq(2)
        expect(inactive_blocks.length).to eq(1)

        expect(active_blocks[0].start_idx).to eq(0)
        expect(active_blocks[1].start_idx).to eq(4)
        expect(inactive_blocks[0].start_idx).to eq(2)
      end
    end

    context "with block containing multiple line types" do
      it "includes all types in the block" do
        diff_lines = [
          Canon::Diff::DiffLine.new(line_number: 0, type: :removed, content: "old", diff_node: diff_node_active),
          Canon::Diff::DiffLine.new(line_number: 1, type: :added, content: "new", diff_node: diff_node_active),
          Canon::Diff::DiffLine.new(line_number: 2, type: :changed, content: "mod", diff_node: diff_node_active),
        ]

        blocks = described_class.build_blocks(diff_lines)

        expect(blocks[0].types).to contain_exactly("-", "+", "!")
      end
    end

    context "with long contiguous block" do
      it "groups all lines into single block" do
        diff_lines = 100.times.map do |i|
          Canon::Diff::DiffLine.new(
            line_number: i,
            type: :removed,
            content: "line #{i}",
            diff_node: diff_node_active,
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
