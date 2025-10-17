# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Diff::DiffContext do
  let(:block1) { Canon::Diff::DiffBlock.new(start_idx: 5, end_idx: 7, types: ["-"]) }
  let(:block2) { Canon::Diff::DiffBlock.new(start_idx: 12, end_idx: 15, types: ["+"]) }

  describe "#initialize" do
    it "creates a context with start and end indices" do
      context = described_class.new(start_idx: 3, end_idx: 20,
                                    blocks: [block1, block2])

      expect(context.start_idx).to eq(3)
      expect(context.end_idx).to eq(20)
      expect(context.blocks).to eq([block1, block2])
    end

    it "accepts a single block" do
      context = described_class.new(start_idx: 5, end_idx: 10, blocks: [block1])

      expect(context.blocks).to eq([block1])
    end

    it "defaults to empty blocks array" do
      context = described_class.new(start_idx: 0, end_idx: 10)

      expect(context.blocks).to eq([])
    end

    it "handles contexts with no diff blocks (pure context lines)" do
      context = described_class.new(start_idx: 0, end_idx: 5, blocks: [])

      expect(context.blocks).to be_empty
      expect(context.size).to eq(6)
    end
  end

  describe "#size" do
    it "returns the number of lines in the context" do
      context = described_class.new(start_idx: 5, end_idx: 10, blocks: [block1])

      expect(context.size).to eq(6) # 10 - 5 + 1
    end

    it "returns 1 for single-line contexts" do
      context = described_class.new(start_idx: 3, end_idx: 3, blocks: [])

      expect(context.size).to eq(1)
    end

    it "handles zero-indexed contexts correctly" do
      context = described_class.new(start_idx: 0, end_idx: 4, blocks: [])

      expect(context.size).to eq(5)
    end

    it "size is independent of number of blocks" do
      context_with_one = described_class.new(start_idx: 0, end_idx: 10,
                                             blocks: [block1])
      context_with_two = described_class.new(start_idx: 0, end_idx: 10,
                                             blocks: [block1, block2])

      expect(context_with_one.size).to eq(11)
      expect(context_with_two.size).to eq(11)
    end
  end

  describe "#block_count" do
    it "returns the number of diff blocks" do
      context = described_class.new(start_idx: 0, end_idx: 20,
                                    blocks: [block1, block2])

      expect(context.block_count).to eq(2)
    end

    it "returns 0 for contexts with no blocks" do
      context = described_class.new(start_idx: 0, end_idx: 10, blocks: [])

      expect(context.block_count).to eq(0)
    end

    it "returns 1 for single block" do
      context = described_class.new(start_idx: 0, end_idx: 10, blocks: [block1])

      expect(context.block_count).to eq(1)
    end
  end

  describe "#includes_type?" do
    it "returns true when any block contains the specified type" do
      context = described_class.new(start_idx: 0, end_idx: 20,
                                    blocks: [block1, block2])

      expect(context.includes_type?("-")).to be true
      expect(context.includes_type?("+")).to be true
    end

    it "returns false when no blocks contain the specified type" do
      context = described_class.new(start_idx: 0, end_idx: 20,
                                    blocks: [block1, block2])

      expect(context.includes_type?("!")).to be false
    end

    it "returns false for empty contexts" do
      context = described_class.new(start_idx: 0, end_idx: 10, blocks: [])

      expect(context.includes_type?("-")).to be false
    end

    it "checks all blocks in the context" do
      block_with_change = Canon::Diff::DiffBlock.new(start_idx: 8, end_idx: 9,
                                                     types: ["!"])
      context = described_class.new(start_idx: 0, end_idx: 20,
                                    blocks: [block1, block_with_change, block2])

      expect(context.includes_type?("!")).to be true
    end
  end

  describe "#gap_to" do
    let(:context1) do
      described_class.new(start_idx: 5, end_idx: 10, blocks: [block1])
    end
    let(:context2) do
      described_class.new(start_idx: 15, end_idx: 20, blocks: [block2])
    end

    it "returns the gap between two non-overlapping contexts" do
      gap = context1.gap_to(context2)

      expect(gap).to eq(4) # 15 - 10 - 1
    end

    it "returns 0 when contexts are adjacent" do
      adjacent_context = described_class.new(start_idx: 11, end_idx: 15,
                                             blocks: [])
      gap = context1.gap_to(adjacent_context)

      expect(gap).to eq(0)
    end

    it "returns 0 when contexts overlap" do
      overlapping_context = described_class.new(start_idx: 8, end_idx: 12,
                                                blocks: [])
      gap = context1.gap_to(overlapping_context)

      expect(gap).to eq(0)
    end

    it "returns infinity when other context is nil" do
      gap = context1.gap_to(nil)

      expect(gap).to eq(Float::INFINITY)
    end

    it "handles reversed order (context2 before context1)" do
      gap = context2.gap_to(context1)

      expect(gap).to eq(4)
    end

    it "returns 0 when contexts are completely overlapping" do
      identical_context = described_class.new(start_idx: 5, end_idx: 10,
                                              blocks: [])
      gap = context1.gap_to(identical_context)

      expect(gap).to eq(0)
    end

    it "handles contexts with gap of 1" do
      close_context = described_class.new(start_idx: 12, end_idx: 15,
                                          blocks: [])
      gap = context1.gap_to(close_context)

      expect(gap).to eq(1)
    end
  end

  describe "#overlaps?" do
    let(:context1) do
      described_class.new(start_idx: 5, end_idx: 10, blocks: [])
    end

    it "returns true when contexts overlap" do
      overlapping = described_class.new(start_idx: 8, end_idx: 12, blocks: [])

      expect(context1.overlaps?(overlapping)).to be true
    end

    it "returns true when one context is contained within another" do
      contained = described_class.new(start_idx: 6, end_idx: 9, blocks: [])

      expect(context1.overlaps?(contained)).to be true
    end

    it "returns true when contexts are identical" do
      identical = described_class.new(start_idx: 5, end_idx: 10, blocks: [])

      expect(context1.overlaps?(identical)).to be true
    end

    it "returns false when contexts are adjacent but not overlapping" do
      adjacent = described_class.new(start_idx: 11, end_idx: 15, blocks: [])

      expect(context1.overlaps?(adjacent)).to be false
    end

    it "returns false when contexts are separate" do
      separate = described_class.new(start_idx: 15, end_idx: 20, blocks: [])

      expect(context1.overlaps?(separate)).to be false
    end

    it "returns false when other context is nil" do
      expect(context1.overlaps?(nil)).to be false
    end

    it "handles overlap at boundaries correctly" do
      # Context ending at 10 should not overlap with context starting at 11
      boundary_context = described_class.new(start_idx: 11, end_idx: 15,
                                             blocks: [])

      expect(context1.overlaps?(boundary_context)).to be false
    end

    it "is symmetric" do
      other_context = described_class.new(start_idx: 8, end_idx: 12, blocks: [])

      expect(context1.overlaps?(other_context)).to eq(other_context.overlaps?(context1))
    end
  end

  describe "#to_h" do
    it "returns a hash representation of the context" do
      context = described_class.new(start_idx: 5, end_idx: 10,
                                    blocks: [block1, block2])

      result = context.to_h

      expect(result).to eq({
                             start_idx: 5,
                             end_idx: 10,
                             blocks: [block1.to_h, block2.to_h],
                           })
    end

    it "includes empty blocks array" do
      context = described_class.new(start_idx: 0, end_idx: 5, blocks: [])

      result = context.to_h

      expect(result[:blocks]).to eq([])
    end

    it "converts all blocks to hashes" do
      context = described_class.new(start_idx: 0, end_idx: 20,
                                    blocks: [block1, block2])

      result = context.to_h

      expect(result[:blocks]).to all(be_a(Hash))
      expect(result[:blocks].length).to eq(2)
    end
  end

  describe "#==" do
    it "returns true for identical contexts" do
      context1 = described_class.new(start_idx: 5, end_idx: 10,
                                     blocks: [block1])
      context2 = described_class.new(start_idx: 5, end_idx: 10,
                                     blocks: [block1])

      expect(context1).to eq(context2)
    end

    it "returns false for different start indices" do
      context1 = described_class.new(start_idx: 5, end_idx: 10,
                                     blocks: [block1])
      context2 = described_class.new(start_idx: 6, end_idx: 10,
                                     blocks: [block1])

      expect(context1).not_to eq(context2)
    end

    it "returns false for different end indices" do
      context1 = described_class.new(start_idx: 5, end_idx: 10,
                                     blocks: [block1])
      context2 = described_class.new(start_idx: 5, end_idx: 11,
                                     blocks: [block1])

      expect(context1).not_to eq(context2)
    end

    it "returns false for different blocks" do
      context1 = described_class.new(start_idx: 5, end_idx: 10,
                                     blocks: [block1])
      context2 = described_class.new(start_idx: 5, end_idx: 10,
                                     blocks: [block2])

      expect(context1).not_to eq(context2)
    end

    it "returns false when comparing to non-DiffContext objects" do
      context = described_class.new(start_idx: 5, end_idx: 10, blocks: [block1])

      expect(context).not_to eq("not a context")
      expect(context).not_to be_nil
      expect(context).not_to eq({ start_idx: 5, end_idx: 10, blocks: [block1] })
    end

    it "compares blocks by value not reference" do
      block1_copy = Canon::Diff::DiffBlock.new(start_idx: 5, end_idx: 7,
                                               types: ["-"])
      context1 = described_class.new(start_idx: 5, end_idx: 10,
                                     blocks: [block1])
      context2 = described_class.new(start_idx: 5, end_idx: 10,
                                     blocks: [block1_copy])

      expect(context1).to eq(context2)
    end
  end

  describe "edge cases" do
    it "handles very large contexts" do
      context = described_class.new(start_idx: 0, end_idx: 100000, blocks: [])

      expect(context.size).to eq(100001)
    end

    it "handles many blocks" do
      many_blocks = Array.new(100) do |i|
        Canon::Diff::DiffBlock.new(start_idx: i * 2, end_idx: i * 2 + 1,
                                   types: ["-"])
      end
      context = described_class.new(start_idx: 0, end_idx: 300,
                                    blocks: many_blocks)

      expect(context.block_count).to eq(100)
    end

    it "handles context at file start (index 0)" do
      context = described_class.new(start_idx: 0, end_idx: 5, blocks: [])

      expect(context.start_idx).to eq(0)
      expect(context.size).to eq(6)
    end
  end
end
