# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/canon/tree_diff"
require_relative "../../../../lib/canon/tree_diff/operations/operation"

RSpec.describe Canon::TreeDiff::Operations::Operation do
  describe "#initialize" do
    it "creates an operation with valid type" do
      operation = described_class.new(type: :insert, node: "test")

      expect(operation.type).to eq(:insert)
      expect(operation[:node]).to eq("test")
    end

    it "raises error for invalid type" do
      expect do
        described_class.new(type: :invalid)
      end.to raise_error(ArgumentError, /Invalid operation type/)
    end

    it "stores metadata" do
      operation = described_class.new(
        type: :update,
        node1: "old",
        node2: "new",
        changes: { value: { old: "a", new: "b" } },
      )

      expect(operation[:node1]).to eq("old")
      expect(operation[:node2]).to eq("new")
      expect(operation[:changes]).to eq({ value: { old: "a", new: "b" } })
    end
  end

  describe "#type?" do
    it "returns true for matching type" do
      operation = described_class.new(type: :insert)

      expect(operation.type?(:insert)).to be true
    end

    it "returns false for non-matching type" do
      operation = described_class.new(type: :insert)

      expect(operation.type?(:delete)).to be false
    end
  end

  describe "#[]" do
    it "retrieves metadata value" do
      operation = described_class.new(type: :move, from: "a", to: "b")

      expect(operation[:from]).to eq("a")
      expect(operation[:to]).to eq("b")
    end

    it "returns nil for non-existent key" do
      operation = described_class.new(type: :insert)

      expect(operation[:nonexistent]).to be_nil
    end
  end

  describe "#==" do
    it "returns true for equal operations" do
      op1 = described_class.new(type: :insert, node: "test")
      op2 = described_class.new(type: :insert, node: "test")

      expect(op1).to eq(op2)
    end

    it "returns false for different types" do
      op1 = described_class.new(type: :insert, node: "test")
      op2 = described_class.new(type: :delete, node: "test")

      expect(op1).not_to eq(op2)
    end

    it "returns false for different metadata" do
      op1 = described_class.new(type: :insert, node: "test1")
      op2 = described_class.new(type: :insert, node: "test2")

      expect(op1).not_to eq(op2)
    end

    it "returns false for non-operation objects" do
      operation = described_class.new(type: :insert)

      expect(operation).not_to eq("not an operation")
    end
  end

  describe "#to_s" do
    it "returns simple string representation" do
      operation = described_class.new(type: :insert)

      expect(operation.to_s).to eq("Operation(insert)")
    end
  end

  describe "#inspect" do
    it "returns detailed string representation" do
      operation = described_class.new(type: :update, node: "test")

      expect(operation.inspect).to include("Canon::TreeDiff::Operations::Operation")
      expect(operation.inspect).to include("type=update")
      expect(operation.inspect).to include("node")
    end
  end

  describe "TYPES constant" do
    it "includes all expected operation types" do
      expect(described_class::TYPES).to include(
        :insert,
        :delete,
        :update,
        :move,
        :merge,
        :split,
        :upgrade,
        :downgrade,
      )
    end
  end
end
