# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/canon/tree_diff/core/tree_node"
require_relative "../../../../lib/canon/tree_diff/core/matching"

RSpec.describe Canon::TreeDiff::Core::Matching do
  let(:tree_node_class) { Canon::TreeDiff::Core::TreeNode }

  describe "#initialize" do
    it "creates empty matching" do
      matching = described_class.new

      expect(matching.pairs).to eq([])
      expect(matching).to be_empty
      expect(matching.size).to eq(0)
    end
  end

  describe "#add" do
    it "adds a valid pair" do
      node1 = tree_node_class.new(label: "div")
      node2 = tree_node_class.new(label: "div")

      matching = described_class.new
      result = matching.add(node1, node2)

      expect(result).to be true
      expect(matching.size).to eq(1)
      expect(matching.pairs).to eq([[node1, node2]])
    end

    it "rejects pair violating one-to-one (node1 already matched)" do
      node1 = tree_node_class.new(label: "div")
      node2a = tree_node_class.new(label: "div")
      node2b = tree_node_class.new(label: "span")

      matching = described_class.new
      matching.add(node1, node2a)
      result = matching.add(node1, node2b)

      expect(result).to be false
      expect(matching.size).to eq(1)
    end

    it "rejects pair violating one-to-one (node2 already matched)" do
      node1a = tree_node_class.new(label: "div")
      node1b = tree_node_class.new(label: "span")
      node2 = tree_node_class.new(label: "div")

      matching = described_class.new
      matching.add(node1a, node2)
      result = matching.add(node1b, node2)

      expect(result).to be false
      expect(matching.size).to eq(1)
    end

    it "rejects pair violating prefix closure" do
      # Tree 1: root1 -> child1
      # Tree 2: root2 -> child2
      # Match root1 to child2 (violates prefix closure)

      root1 = tree_node_class.new(label: "root")
      child1 = tree_node_class.new(label: "child")
      root1.add_child(child1)

      root2 = tree_node_class.new(label: "root")
      child2 = tree_node_class.new(label: "child")
      root2.add_child(child2)

      matching = described_class.new
      matching.add(child1, child2)

      # Try to match root1 with child2 (child2's parent is root2)
      result = matching.add(root1, child2)

      expect(result).to be false
    end

    it "allows matching with correct prefix closure" do
      root1 = tree_node_class.new(label: "root")
      child1 = tree_node_class.new(label: "child")
      root1.add_child(child1)

      root2 = tree_node_class.new(label: "root")
      child2 = tree_node_class.new(label: "child")
      root2.add_child(child2)

      matching = described_class.new
      matching.add(root1, root2)
      result = matching.add(child1, child2)

      expect(result).to be true
      expect(matching.size).to eq(2)
    end
  end

  describe "#remove" do
    it "removes an existing pair" do
      node1 = tree_node_class.new(label: "div")
      node2 = tree_node_class.new(label: "div")

      matching = described_class.new
      matching.add(node1, node2)

      result = matching.remove(node1, node2)

      expect(result).to be true
      expect(matching).to be_empty
    end

    it "returns false for non-existent pair" do
      node1 = tree_node_class.new(label: "div")
      node2 = tree_node_class.new(label: "div")

      matching = described_class.new

      result = matching.remove(node1, node2)

      expect(result).to be false
    end
  end

  describe "#matched1?" do
    it "returns true for matched node from tree1" do
      node1 = tree_node_class.new(label: "div")
      node2 = tree_node_class.new(label: "div")

      matching = described_class.new
      matching.add(node1, node2)

      expect(matching.matched1?(node1)).to be true
    end

    it "returns false for unmatched node from tree1" do
      node1 = tree_node_class.new(label: "div")

      matching = described_class.new

      expect(matching.matched1?(node1)).to be false
    end
  end

  describe "#matched2?" do
    it "returns true for matched node from tree2" do
      node1 = tree_node_class.new(label: "div")
      node2 = tree_node_class.new(label: "div")

      matching = described_class.new
      matching.add(node1, node2)

      expect(matching.matched2?(node2)).to be true
    end

    it "returns false for unmatched node from tree2" do
      node2 = tree_node_class.new(label: "div")

      matching = described_class.new

      expect(matching.matched2?(node2)).to be false
    end
  end

  describe "#match_for1" do
    it "returns matched node from tree2" do
      node1 = tree_node_class.new(label: "div")
      node2 = tree_node_class.new(label: "div")

      matching = described_class.new
      matching.add(node1, node2)

      expect(matching.match_for1(node1)).to eq(node2)
    end

    it "returns nil for unmatched node" do
      node1 = tree_node_class.new(label: "div")

      matching = described_class.new

      expect(matching.match_for1(node1)).to be_nil
    end
  end

  describe "#match_for2" do
    it "returns matched node from tree1" do
      node1 = tree_node_class.new(label: "div")
      node2 = tree_node_class.new(label: "div")

      matching = described_class.new
      matching.add(node1, node2)

      expect(matching.match_for2(node2)).to eq(node1)
    end

    it "returns nil for unmatched node" do
      node2 = tree_node_class.new(label: "div")

      matching = described_class.new

      expect(matching.match_for2(node2)).to be_nil
    end
  end

  describe "#unmatched1" do
    it "returns unmatched nodes from tree1" do
      node1a = tree_node_class.new(label: "div")
      node1b = tree_node_class.new(label: "span")
      node1c = tree_node_class.new(label: "p")
      node2 = tree_node_class.new(label: "div")

      matching = described_class.new
      matching.add(node1a, node2)

      unmatched = matching.unmatched1([node1a, node1b, node1c])

      expect(unmatched).to contain_exactly(node1b, node1c)
    end
  end

  describe "#unmatched2" do
    it "returns unmatched nodes from tree2" do
      node1 = tree_node_class.new(label: "div")
      node2a = tree_node_class.new(label: "div")
      node2b = tree_node_class.new(label: "span")
      node2c = tree_node_class.new(label: "p")

      matching = described_class.new
      matching.add(node1, node2a)

      unmatched = matching.unmatched2([node2a, node2b, node2c])

      expect(unmatched).to contain_exactly(node2b, node2c)
    end
  end

  describe "#each" do
    it "iterates over all pairs" do
      node1a = tree_node_class.new(label: "div")
      node1b = tree_node_class.new(label: "span")
      node2a = tree_node_class.new(label: "div")
      node2b = tree_node_class.new(label: "span")

      matching = described_class.new
      matching.add(node1a, node2a)
      matching.add(node1b, node2b)

      pairs = []
      matching.each { |n1, n2| pairs << [n1, n2] }

      expect(pairs).to eq([[node1a, node2a], [node1b, node2b]])
    end
  end

  describe "#valid?" do
    it "returns true for valid matching" do
      root1 = tree_node_class.new(label: "root")
      child1 = tree_node_class.new(label: "child")
      root1.add_child(child1)

      root2 = tree_node_class.new(label: "root")
      child2 = tree_node_class.new(label: "child")
      root2.add_child(child2)

      matching = described_class.new
      matching.add(root1, root2)
      matching.add(child1, child2)

      expect(matching).to be_valid
    end

    it "returns true for empty matching" do
      matching = described_class.new

      expect(matching).to be_valid
    end
  end

  describe "#one_to_one?" do
    it "returns true when each node appears at most once" do
      node1a = tree_node_class.new(label: "div")
      node1b = tree_node_class.new(label: "span")
      node2a = tree_node_class.new(label: "div")
      node2b = tree_node_class.new(label: "span")

      matching = described_class.new
      matching.add(node1a, node2a)
      matching.add(node1b, node2b)

      expect(matching.one_to_one?).to be true
    end

    it "detects violation when manipulated directly" do
      node1 = tree_node_class.new(label: "div")
      node2 = tree_node_class.new(label: "div")
      node3 = tree_node_class.new(label: "span")

      matching = described_class.new
      matching.add(node1, node2)

      # Manually violate constraint (bypassing add validation)
      # We need to update both pairs and maps to create an invalid state
      matching.instance_variable_get(:@pairs) << [node1, node3]
      matching.instance_variable_get(:@tree1_map)[node1] = node3  # Now node1 maps to node3, but pairs has both

      expect(matching.one_to_one?).to be false
    end
  end

  describe "#prefix_closure?" do
    it "returns true when ancestors match correctly" do
      root1 = tree_node_class.new(label: "root")
      child1 = tree_node_class.new(label: "child")
      grandchild1 = tree_node_class.new(label: "grandchild")
      root1.add_child(child1)
      child1.add_child(grandchild1)

      root2 = tree_node_class.new(label: "root")
      child2 = tree_node_class.new(label: "child")
      grandchild2 = tree_node_class.new(label: "grandchild")
      root2.add_child(child2)
      child2.add_child(grandchild2)

      matching = described_class.new
      matching.add(root1, root2)
      matching.add(child1, child2)
      matching.add(grandchild1, grandchild2)

      expect(matching.prefix_closure?).to be true
    end

    it "detects violation when ancestor matches incorrectly" do
      root1 = tree_node_class.new(label: "root1")
      child1 = tree_node_class.new(label: "child")
      root1.add_child(child1)

      root2a = tree_node_class.new(label: "root2a")
      root2b = tree_node_class.new(label: "root2b")
      child2 = tree_node_class.new(label: "child")
      root2a.add_child(child2)

      matching = described_class.new
      matching.add(child1, child2)

      # Manually add incorrect parent match (bypassing add validation)
      matching.instance_variable_get(:@pairs) << [root1, root2b]
      matching.instance_variable_get(:@tree1_map)[root1] = root2b
      matching.instance_variable_get(:@tree2_map)[root2b] = root1

      expect(matching.prefix_closure?).to be false
    end
  end

  describe "#to_a" do
    it "returns array of pairs" do
      node1 = tree_node_class.new(label: "div")
      node2 = tree_node_class.new(label: "div")

      matching = described_class.new
      matching.add(node1, node2)

      array = matching.to_a

      expect(array).to eq([[node1, node2]])
      expect(array).not_to be(matching.pairs)
    end
  end

  describe "#inspect" do
    it "provides readable representation" do
      node1 = tree_node_class.new(label: "div")
      node2 = tree_node_class.new(label: "span")

      matching = described_class.new
      matching.add(node1, node2)

      result = matching.inspect

      expect(result).to include("Matching")
      expect(result).to include("div")
      expect(result).to include("span")
    end
  end

  describe "complex scenarios" do
    it "handles multiple levels of nesting" do
      # Build tree1
      root1 = tree_node_class.new(label: "html")
      body1 = tree_node_class.new(label: "body")
      div1 = tree_node_class.new(label: "div")
      p1 = tree_node_class.new(label: "p")
      root1.add_child(body1)
      body1.add_child(div1)
      div1.add_child(p1)

      # Build tree2
      root2 = tree_node_class.new(label: "html")
      body2 = tree_node_class.new(label: "body")
      div2 = tree_node_class.new(label: "div")
      p2 = tree_node_class.new(label: "p")
      root2.add_child(body2)
      body2.add_child(div2)
      div2.add_child(p2)

      matching = described_class.new
      expect(matching.add(root1, root2)).to be true
      expect(matching.add(body1, body2)).to be true
      expect(matching.add(div1, div2)).to be true
      expect(matching.add(p1, p2)).to be true

      expect(matching.size).to eq(4)
      expect(matching).to be_valid
    end

    it "handles partial matching" do
      # Tree1: root -> [child1, child2, child3]
      root1 = tree_node_class.new(label: "root")
      child1a = tree_node_class.new(label: "child1")
      child1b = tree_node_class.new(label: "child2")
      child1c = tree_node_class.new(label: "child3")
      root1.add_child(child1a)
      root1.add_child(child1b)
      root1.add_child(child1c)

      # Tree2: root -> [child1, child3]
      root2 = tree_node_class.new(label: "root")
      child2a = tree_node_class.new(label: "child1")
      child2c = tree_node_class.new(label: "child3")
      root2.add_child(child2a)
      root2.add_child(child2c)

      matching = described_class.new
      matching.add(root1, root2)
      matching.add(child1a, child2a)
      matching.add(child1c, child2c)

      # child1b is unmatched
      expect(matching.size).to eq(3)
      expect(matching.matched1?(child1b)).to be false
      expect(matching).to be_valid
    end
  end
end
