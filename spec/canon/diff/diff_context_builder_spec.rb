# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Diff::DiffContextBuilder do
  let(:diff_node_normative) do
    Canon::Diff::DiffNode.new(
      node1: "old",
      node2: "new",
      dimension: :text_content,
      reason: "Text differs",
    ).tap { |node| node.normative = true }
  end

  let(:diff_node_informative) do
    Canon::Diff::DiffNode.new(
      node1: "a='1' b='2'",
      node2: "b='2' a='1'",
      dimension: :attribute_order,
      reason: "Order differs",
    ).tap { |node| node.normative = false }
  end

  describe ".build_contexts" do
    context "with empty blocks" do
      it "returns empty array" do
        contexts = described_class.build_contexts([], [])

        expect(contexts).to be_empty
      end
    end

    context "with single block" do
      it "creates context with default context lines" do
        all_lines = Array.new(10) do |i|
          Canon::Diff::DiffLine.new(
            line_number: i,
            type: i == 5 ? :removed : :unchanged,
            content: "line #{i}",
            diff_node: i == 5 ? diff_node_normative : nil,
          )
        end

        blocks = [
          Canon::Diff::DiffBlock.new(
            start_idx: 5,
            end_idx: 5,
            types: ["-"],
            diff_lines: [all_lines[5]],
          ).tap { |b| b.normative = true },
        ]

        contexts = described_class.build_contexts(blocks, all_lines,
                                                  context_lines: 3)

        expect(contexts.length).to eq(1)
        expect(contexts[0].start_idx).to eq(2) # 5 - 3
        expect(contexts[0].end_idx).to eq(8)   # 5 + 3
        expect(contexts[0].blocks.length).to eq(1)
        expect(contexts[0]).to be_normative
      end
    end

    context "with context_lines at file boundaries" do
      it "doesn't go below 0" do
        all_lines = Array.new(5) do |i|
          Canon::Diff::DiffLine.new(
            line_number: i,
            type: i == 0 ? :removed : :unchanged,
            content: "line #{i}",
            diff_node: i == 0 ? diff_node_normative : nil,
          )
        end

        blocks = [
          Canon::Diff::DiffBlock.new(
            start_idx: 0,
            end_idx: 0,
            types: ["-"],
            diff_lines: [all_lines[0]],
          ).tap { |b| b.normative = true },
        ]

        contexts = described_class.build_contexts(blocks, all_lines,
                                                  context_lines: 5)

        expect(contexts[0].start_idx).to eq(0) # Capped at 0
        expect(contexts[0].end_idx).to eq(4)   # 0 + 5, capped at length-1
      end

      it "doesn't go beyond array length" do
        all_lines = Array.new(5) do |i|
          Canon::Diff::DiffLine.new(
            line_number: i,
            type: i == 4 ? :removed : :unchanged,
            content: "line #{i}",
            diff_node: i == 4 ? diff_node_normative : nil,
          )
        end

        blocks = [
          Canon::Diff::DiffBlock.new(
            start_idx: 4,
            end_idx: 4,
            types: ["-"],
            diff_lines: [all_lines[4]],
          ).tap { |b| b.normative = true },
        ]

        contexts = described_class.build_contexts(blocks, all_lines,
                                                  context_lines: 5)

        expect(contexts[0].start_idx).to eq(0) # 4 - 5, capped at 0
        expect(contexts[0].end_idx).to eq(4)   # Capped at length-1
      end
    end

    context "without grouping (grouping_lines: nil)" do
      it "creates separate context for each block" do
        all_lines = Array.new(20) do |i|
          Canon::Diff::DiffLine.new(
            line_number: i,
            type: [5, 15].include?(i) ? :removed : :unchanged,
            content: "line #{i}",
            diff_node: [5, 15].include?(i) ? diff_node_normative : nil,
          )
        end

        blocks = [
          Canon::Diff::DiffBlock.new(
            start_idx: 5,
            end_idx: 5,
            types: ["-"],
            diff_lines: [all_lines[5]],
          ).tap { |b| b.normative = true },
          Canon::Diff::DiffBlock.new(
            start_idx: 15,
            end_idx: 15,
            types: ["-"],
            diff_lines: [all_lines[15]],
          ).tap { |b| b.normative = true },
        ]

        contexts = described_class.build_contexts(blocks, all_lines,
                                                  context_lines: 2, grouping_lines: nil)

        expect(contexts.length).to eq(2)
        expect(contexts[0].blocks.length).to eq(1)
        expect(contexts[1].blocks.length).to eq(1)
      end
    end

    context "with grouping (grouping_lines specified)" do
      it "groups blocks within threshold" do
        all_lines = Array.new(20) do |i|
          Canon::Diff::DiffLine.new(
            line_number: i,
            type: [5, 8].include?(i) ? :removed : :unchanged,
            content: "line #{i}",
            diff_node: [5, 8].include?(i) ? diff_node_normative : nil,
          )
        end

        blocks = [
          Canon::Diff::DiffBlock.new(
            start_idx: 5,
            end_idx: 5,
            types: ["-"],
            diff_lines: [all_lines[5]],
          ).tap { |b| b.normative = true },
          Canon::Diff::DiffBlock.new(
            start_idx: 8,
            end_idx: 8,
            types: ["-"],
            diff_lines: [all_lines[8]],
          ).tap { |b| b.normative = true },
        ]

        # Gap between blocks: 8 - 5 - 1 = 2 lines
        # With grouping_lines: 3, they should be grouped
        contexts = described_class.build_contexts(blocks, all_lines,
                                                  context_lines: 1, grouping_lines: 3)

        expect(contexts.length).to eq(1)
        expect(contexts[0].blocks.length).to eq(2)
      end

      it "doesn't group blocks beyond threshold" do
        all_lines = Array.new(20) do |i|
          Canon::Diff::DiffLine.new(
            line_number: i,
            type: [5, 15].include?(i) ? :removed : :unchanged,
            content: "line #{i}",
            diff_node: [5, 15].include?(i) ? diff_node_normative : nil,
          )
        end

        blocks = [
          Canon::Diff::DiffBlock.new(
            start_idx: 5,
            end_idx: 5,
            types: ["-"],
            diff_lines: [all_lines[5]],
          ).tap { |b| b.normative = true },
          Canon::Diff::DiffBlock.new(
            start_idx: 15,
            end_idx: 15,
            types: ["-"],
            diff_lines: [all_lines[15]],
          ).tap { |b| b.normative = true },
        ]

        # Gap between blocks: 15 - 5 - 1 = 9 lines
        # With grouping_lines: 5, they should NOT be grouped
        contexts = described_class.build_contexts(blocks, all_lines,
                                                  context_lines: 1, grouping_lines: 5)

        expect(contexts.length).to eq(2)
        expect(contexts[0].blocks.length).to eq(1)
        expect(contexts[1].blocks.length).to eq(1)
      end

      it "groups multiple consecutive blocks" do
        all_lines = Array.new(30) do |i|
          Canon::Diff::DiffLine.new(
            line_number: i,
            type: [5, 8, 11].include?(i) ? :removed : :unchanged,
            content: "line #{i}",
            diff_node: [5, 8, 11].include?(i) ? diff_node_normative : nil,
          )
        end

        blocks = [
          Canon::Diff::DiffBlock.new(
            start_idx: 5,
            end_idx: 5,
            types: ["-"],
            diff_lines: [all_lines[5]],
          ).tap { |b| b.normative = true },
          Canon::Diff::DiffBlock.new(
            start_idx: 8,
            end_idx: 8,
            types: ["-"],
            diff_lines: [all_lines[8]],
          ).tap { |b| b.normative = true },
          Canon::Diff::DiffBlock.new(
            start_idx: 11,
            end_idx: 11,
            types: ["-"],
            diff_lines: [all_lines[11]],
          ).tap { |b| b.normative = true },
        ]

        # All gaps are 2 lines, with grouping_lines: 3, all should group
        contexts = described_class.build_contexts(blocks, all_lines,
                                                  context_lines: 1, grouping_lines: 3)

        expect(contexts.length).to eq(1)
        expect(contexts[0].blocks.length).to eq(3)
      end
    end

    context "with mixed normative/informative blocks" do
      it "marks context as normative if ANY block is normative" do
        all_lines = Array.new(10) do |i|
          type = [3, 5].include?(i) ? :removed : :unchanged
          node = if i == 3
                   diff_node_informative
                 elsif i == 5
                   diff_node_normative
                 end

          Canon::Diff::DiffLine.new(
            line_number: i,
            type: type,
            content: "line #{i}",
            diff_node: node,
          )
        end

        blocks = [
          Canon::Diff::DiffBlock.new(
            start_idx: 3,
            end_idx: 3,
            types: ["-"],
            diff_lines: [all_lines[3]],
          ).tap { |b| b.normative = false },
          Canon::Diff::DiffBlock.new(
            start_idx: 5,
            end_idx: 5,
            types: ["-"],
            diff_lines: [all_lines[5]],
          ).tap { |b| b.normative = true },
        ]

        contexts = described_class.build_contexts(blocks, all_lines,
                                                  context_lines: 1, grouping_lines: 3)

        expect(contexts.length).to eq(1)
        expect(contexts[0]).to be_normative
      end

      it "marks context as informative if ALL blocks are informative" do
        all_lines = Array.new(10) do |i|
          type = [3, 5].include?(i) ? :removed : :unchanged
          node = [3, 5].include?(i) ? diff_node_informative : nil

          Canon::Diff::DiffLine.new(
            line_number: i,
            type: type,
            content: "line #{i}",
            diff_node: node,
          )
        end

        blocks = [
          Canon::Diff::DiffBlock.new(
            start_idx: 3,
            end_idx: 3,
            types: ["-"],
            diff_lines: [all_lines[3]],
          ).tap { |b| b.normative = false },
          Canon::Diff::DiffBlock.new(
            start_idx: 5,
            end_idx: 5,
            types: ["-"],
            diff_lines: [all_lines[5]],
          ).tap { |b| b.normative = false },
        ]

        contexts = described_class.build_contexts(blocks, all_lines,
                                                  context_lines: 1, grouping_lines: 3)

        expect(contexts.length).to eq(1)
        expect(contexts[0]).to be_informative
      end
    end

    context "edge cases" do
      it "handles context_lines: 0" do
        all_lines = Array.new(10) do |i|
          Canon::Diff::DiffLine.new(
            line_number: i,
            type: i == 5 ? :removed : :unchanged,
            content: "line #{i}",
            diff_node: i == 5 ? diff_node_normative : nil,
          )
        end

        blocks = [
          Canon::Diff::DiffBlock.new(
            start_idx: 5,
            end_idx: 5,
            types: ["-"],
            diff_lines: [all_lines[5]],
          ).tap { |b| b.normative = true },
        ]

        contexts = described_class.build_contexts(blocks, all_lines,
                                                  context_lines: 0)

        expect(contexts[0].start_idx).to eq(5)
        expect(contexts[0].end_idx).to eq(5)
      end

      it "handles multi-line blocks" do
        all_lines = Array.new(10) do |i|
          Canon::Diff::DiffLine.new(
            line_number: i,
            type: (3..5).cover?(i) ? :removed : :unchanged,
            content: "line #{i}",
            diff_node: (3..5).cover?(i) ? diff_node_normative : nil,
          )
        end

        blocks = [
          Canon::Diff::DiffBlock.new(
            start_idx: 3,
            end_idx: 5,
            types: ["-"],
            diff_lines: all_lines[3..5],
          ).tap { |b| b.normative = true },
        ]

        contexts = described_class.build_contexts(blocks, all_lines,
                                                  context_lines: 1)

        expect(contexts[0].start_idx).to eq(2) # 3 - 1
        expect(contexts[0].end_idx).to eq(6)   # 5 + 1
      end
    end
  end
end
