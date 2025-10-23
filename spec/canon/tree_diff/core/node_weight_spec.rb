# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/canon/tree_diff/core/tree_node"
require_relative "../../../../lib/canon/tree_diff/core/node_weight"

RSpec.describe Canon::TreeDiff::Core::NodeWeight do
  let(:tree_node_class) { Canon::TreeDiff::Core::TreeNode }

  describe "#initialize" do
    it "computes weight for simple element node" do
      node = tree_node_class.new(label: "div")
      weight = described_class.new(node)

      expect(weight.value).to eq(1.0)
    end

    it "computes weight for text node with content" do
      node = tree_node_class.new(label: "text", value: "Hello World")
      weight = described_class.new(node)

      # 1 + log(12) = 1 + log(13) ≈ 3.56
      expect(weight.value).to be > 1.0
      expect(weight.value).to be < 5.0
    end

    it "computes weight for empty text node" do
      node = tree_node_class.new(label: "text", value: "")
      weight = described_class.new(node)

      expect(weight.value).to eq(1.0)
    end

    it "computes weight for element with children" do
      root = tree_node_class.new(label: "root")
      child1 = tree_node_class.new(label: "child1")
      child2 = tree_node_class.new(label: "child2")

      root.add_child(child1)
      root.add_child(child2)

      weight = described_class.new(root)

      # 1 + (1 + 1) = 3.0
      expect(weight.value).to eq(3.0)
    end

    it "computes weight recursively for nested structure" do
      root = tree_node_class.new(label: "root")
      child = tree_node_class.new(label: "child")
      grandchild1 = tree_node_class.new(label: "grandchild1")
      grandchild2 = tree_node_class.new(label: "grandchild2")

      root.add_child(child)
      child.add_child(grandchild1)
      child.add_child(grandchild2)

      weight = described_class.new(root)

      # root: 1 + child_weight
      # child: 1 + (1 + 1) = 3
      # root: 1 + 3 = 4
      expect(weight.value).to eq(4.0)
    end
  end

  describe ".for" do
    it "computes and caches weight on node" do
      node = tree_node_class.new(label: "div")

      weight1 = described_class.for(node)
      weight2 = described_class.for(node)

      expect(weight1).to be(weight2)
      expect(node.weight).to eq(weight1)
    end

    it "returns cached weight if already computed" do
      node = tree_node_class.new(label: "div")
      cached = described_class.new(node)
      node.weight = cached

      result = described_class.for(node)

      expect(result).to be(cached)
    end
  end

  describe "#<=>" do
    it "compares weights by value" do
      node1 = tree_node_class.new(label: "div")
      node2 = tree_node_class.new(label: "div")
      child = tree_node_class.new(label: "child")
      node2.add_child(child)

      weight1 = described_class.new(node1) # 1.0
      weight2 = described_class.new(node2) # 2.0

      expect(weight1 <=> weight2).to eq(-1)
      expect(weight2 <=> weight1).to eq(1)
    end

    it "returns 0 for equal weights" do
      node1 = tree_node_class.new(label: "div")
      node2 = tree_node_class.new(label: "span")

      weight1 = described_class.new(node1)
      weight2 = described_class.new(node2)

      expect(weight1 <=> weight2).to eq(0)
    end
  end

  describe "#==" do
    it "returns true for equal weights" do
      node1 = tree_node_class.new(label: "div")
      node2 = tree_node_class.new(label: "span")

      weight1 = described_class.new(node1)
      weight2 = described_class.new(node2)

      expect(weight1).to eq(weight2)
    end

    it "returns false for different weights" do
      node1 = tree_node_class.new(label: "div")
      node2 = tree_node_class.new(label: "div")
      node2.add_child(tree_node_class.new(label: "child"))

      weight1 = described_class.new(node1)
      weight2 = described_class.new(node2)

      expect(weight1).not_to eq(weight2)
    end
  end

  describe "#to_f" do
    it "returns numeric value" do
      node = tree_node_class.new(label: "div")
      weight = described_class.new(node)

      expect(weight.to_f).to eq(1.0)
      expect(weight.to_f).to be_a(Float)
    end
  end

  describe "#to_i" do
    it "returns integer value" do
      node = tree_node_class.new(label: "div")
      child1 = tree_node_class.new(label: "child1")
      child2 = tree_node_class.new(label: "child2")
      node.add_child(child1)
      node.add_child(child2)

      weight = described_class.new(node)

      expect(weight.to_i).to eq(3)
      expect(weight.to_i).to be_a(Integer)
    end
  end

  describe "text node weights" do
    it "grows logarithmically with text length" do
      short_text = tree_node_class.new(label: "text", value: "Hi")
      medium_text = tree_node_class.new(label: "text", value: "A" * 100)
      long_text = tree_node_class.new(label: "text", value: "A" * 1000)

      short_weight = described_class.new(short_text).value
      medium_weight = described_class.new(medium_text).value
      long_weight = described_class.new(long_text).value

      expect(short_weight).to be < medium_weight
      expect(medium_weight).to be < long_weight

      # Logarithmic growth means doubling length doesn't double weight
      ratio1 = medium_weight / short_weight
      ratio2 = long_weight / medium_weight
      expect(ratio2).to be < ratio1
    end

    it "uses natural logarithm" do
      # For text length = e - 1 ≈ 1.718
      # Weight should be 1 + log(e) = 1 + 1 = 2.0
      text_length = (Math::E - 1).to_i
      node = tree_node_class.new(label: "text", value: "x" * text_length)
      weight = described_class.new(node).value

      expected = 1.0 + Math.log(text_length + 1)
      expect(weight).to be_within(0.01).of(expected)
    end
  end

  describe "element node weights" do
    it "sums children weights" do
      parent = tree_node_class.new(label: "parent")
      child1 = tree_node_class.new(label: "child1")
      child2 = tree_node_class.new(label: "child2")
      child3 = tree_node_class.new(label: "child3")

      parent.add_child(child1)
      parent.add_child(child2)
      parent.add_child(child3)

      weight = described_class.new(parent).value

      # 1 + (1 + 1 + 1) = 4.0
      expect(weight).to eq(4.0)
    end

    it "handles mixed text and element children" do
      parent = tree_node_class.new(label: "parent")
      element_child = tree_node_class.new(label: "div")
      text_child = tree_node_class.new(label: "text", value: "Hello")

      parent.add_child(element_child)
      parent.add_child(text_child)

      weight = described_class.new(parent).value

      # 1 + (1 + text_weight)
      # text_weight = 1 + log(6) ≈ 1 + 1.79 = 2.79
      # total ≈ 1 + 1 + 2.79 = 4.79
      expect(weight).to be > 3.5
      expect(weight).to be < 5.0
    end
  end

  describe "sorting by weight" do
    it "allows sorting nodes by weight" do
      leaf = tree_node_class.new(label: "leaf")

      small = tree_node_class.new(label: "small")
      small.add_child(tree_node_class.new(label: "child"))

      large = tree_node_class.new(label: "large")
      large.add_child(tree_node_class.new(label: "child1"))
      large.add_child(tree_node_class.new(label: "child2"))
      large.add_child(tree_node_class.new(label: "child3"))

      weights = [leaf, small, large].map { |n| described_class.new(n) }

      sorted = weights.sort.reverse

      expect(sorted[0].value).to eq(4.0) # large
      expect(sorted[1].value).to eq(2.0) # small
      expect(sorted[2].value).to eq(1.0) # leaf
    end
  end
end
