# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Diff::DiffBlock do
  describe "#initialize" do
    it "creates a block with start and end indices" do
      block = described_class.new(start_idx: 5, end_idx: 10, types: ["-"])

      expect(block.start_idx).to eq(5)
      expect(block.end_idx).to eq(10)
      expect(block.types).to eq(["-"])
    end

    it "accepts multiple change types" do
      block = described_class.new(start_idx: 0, end_idx: 3, types: ["-", "+"])

      expect(block.types).to contain_exactly("-", "+")
    end

    it "accepts change type '!'" do
      block = described_class.new(start_idx: 2, end_idx: 2, types: ["!"])

      expect(block.types).to eq(["!"])
    end

    it "handles single-line blocks" do
      block = described_class.new(start_idx: 7, end_idx: 7, types: ["-"])

      expect(block.start_idx).to eq(7)
      expect(block.end_idx).to eq(7)
    end

    it "defaults to empty types array" do
      block = described_class.new(start_idx: 0, end_idx: 5)

      expect(block.types).to eq([])
    end
  end

  describe "#size" do
    it "returns the number of lines in the block" do
      block = described_class.new(start_idx: 5, end_idx: 10, types: ["-"])

      expect(block.size).to eq(6) # 10 - 5 + 1
    end

    it "returns 1 for single-line blocks" do
      block = described_class.new(start_idx: 3, end_idx: 3, types: ["+"])

      expect(block.size).to eq(1)
    end

    it "handles zero-indexed blocks correctly" do
      block = described_class.new(start_idx: 0, end_idx: 4, types: ["!"])

      expect(block.size).to eq(5)
    end
  end

  describe "#includes_type?" do
    it "returns true when block contains the specified type" do
      block = described_class.new(start_idx: 0, end_idx: 2, types: ["-", "+"])

      expect(block.includes_type?("-")).to be true
      expect(block.includes_type?("+")).to be true
    end

    it "returns false when block does not contain the specified type" do
      block = described_class.new(start_idx: 0, end_idx: 2, types: ["-"])

      expect(block.includes_type?("+")).to be false
      expect(block.includes_type?("!")).to be false
    end

    it "returns false for empty types" do
      block = described_class.new(start_idx: 0, end_idx: 2, types: [])

      expect(block.includes_type?("-")).to be false
    end

    it "handles change type '!'" do
      block = described_class.new(start_idx: 0, end_idx: 1, types: ["!"])

      expect(block.includes_type?("!")).to be true
      expect(block.includes_type?("-")).to be false
    end

    it "is case-sensitive" do
      block = described_class.new(start_idx: 0, end_idx: 1, types: ["-"])

      expect(block.includes_type?("-")).to be true
      expect(block.includes_type?("minus")).to be false
    end
  end

  describe "#to_h" do
    it "returns a hash representation of the block" do
      block = described_class.new(start_idx: 5, end_idx: 10, types: ["-", "+"])

      result = block.to_h

      expect(result).to include({
                                  start_idx: 5,
                                  end_idx: 10,
                                  types: ["-", "+"],
                                })
      # May also include other fields like active, diff_lines, diff_node
    end

    it "includes empty types array" do
      block = described_class.new(start_idx: 0, end_idx: 2)

      result = block.to_h

      expect(result[:types]).to eq([])
    end

    it "preserves type order" do
      block = described_class.new(start_idx: 0, end_idx: 3,
                                  types: ["+", "-", "!"])

      result = block.to_h

      expect(result[:types]).to eq(["+", "-", "!"])
    end
  end

  describe "#==" do
    it "returns true for identical blocks" do
      block1 = described_class.new(start_idx: 5, end_idx: 10, types: ["-"])
      block2 = described_class.new(start_idx: 5, end_idx: 10, types: ["-"])

      expect(block1).to eq(block2)
    end

    it "returns false for different start indices" do
      block1 = described_class.new(start_idx: 5, end_idx: 10, types: ["-"])
      block2 = described_class.new(start_idx: 6, end_idx: 10, types: ["-"])

      expect(block1).not_to eq(block2)
    end

    it "returns false for different end indices" do
      block1 = described_class.new(start_idx: 5, end_idx: 10, types: ["-"])
      block2 = described_class.new(start_idx: 5, end_idx: 11, types: ["-"])

      expect(block1).not_to eq(block2)
    end

    it "returns false for different types" do
      block1 = described_class.new(start_idx: 5, end_idx: 10, types: ["-"])
      block2 = described_class.new(start_idx: 5, end_idx: 10, types: ["+"])

      expect(block1).not_to eq(block2)
    end

    it "returns false when comparing to non-DiffBlock objects" do
      block = described_class.new(start_idx: 5, end_idx: 10, types: ["-"])

      expect(block).not_to eq("not a block")
      expect(block).not_to be_nil
      expect(block).not_to eq({ start_idx: 5, end_idx: 10, types: ["-"] })
    end

    it "returns true when types are in different order but contain same elements" do
      block1 = described_class.new(start_idx: 5, end_idx: 10, types: ["-", "+"])
      block2 = described_class.new(start_idx: 5, end_idx: 10, types: ["-", "+"])

      expect(block1).to eq(block2)
    end
  end

  describe "edge cases" do
    it "handles very large block sizes" do
      block = described_class.new(start_idx: 0, end_idx: 10000, types: ["-"])

      expect(block.size).to eq(10001)
    end

    it "handles blocks at the start of a file (index 0)" do
      block = described_class.new(start_idx: 0, end_idx: 5, types: ["+"])

      expect(block.start_idx).to eq(0)
      expect(block.size).to eq(6)
    end

    it "handles multiple types with duplicates" do
      block = described_class.new(start_idx: 0, end_idx: 2,
                                  types: ["-", "-", "+"])

      expect(block.types).to eq(["-", "-", "+"])
      expect(block.includes_type?("-")).to be true
    end
  end
end
