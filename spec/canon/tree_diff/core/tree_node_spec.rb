# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/canon/tree_diff/core/tree_node"

RSpec.describe Canon::TreeDiff::Core::TreeNode do
  describe "#initialize" do
    it "creates a node with label" do
      node = described_class.new(label: "div")
      expect(node.label).to eq("div")
    end

    it "creates a node with value" do
      node = described_class.new(label: "text", value: "Hello")
      expect(node.value).to eq("Hello")
    end

    it "creates a node with children" do
      child = described_class.new(label: "span")
      node = described_class.new(label: "div", children: [child])

      expect(node.children).to eq([child])
      expect(child.parent).to eq(node)
    end

    it "creates a node with attributes" do
      node = described_class.new(
        label: "div",
        attributes: { "class" => "container", "id" => "main" }
      )

      expect(node.attributes).to eq({ "class" => "container", "id" => "main" })
    end

    it "creates a node with xid" do
      node = described_class.new(label: "div", xid: "element-123")
      expect(node.xid).to eq("element-123")
    end

    it "sets parent for all children" do
      child1 = described_class.new(label: "span")
      child2 = described_class.new(label: "p")
      parent = described_class.new(label: "div", children: [child1, child2])

      expect(child1.parent).to eq(parent)
      expect(child2.parent).to eq(parent)
    end
  end

  describe "#leaf?" do
    it "returns true for node without children" do
      node = described_class.new(label: "div")
      expect(node.leaf?).to be true
    end

    it "returns false for node with children" do
      child = described_class.new(label: "span")
      node = described_class.new(label: "div", children: [child])
      expect(node.leaf?).to be false
    end
  end

  describe "#text?" do
    it "returns true for leaf node with value" do
      node = described_class.new(label: "text", value: "Hello")
      expect(node.text?).to be true
    end

    it "returns false for leaf node without value" do
      node = described_class.new(label: "div")
      expect(node.text?).to be false
    end

    it "returns false for node with children" do
      child = described_class.new(label: "span")
      node = described_class.new(label: "div", children: [child], value: "text")
      expect(node.text?).to be false
    end
  end

  describe "#element?" do
    it "returns true for node with children" do
      child = described_class.new(label: "span")
      node = described_class.new(label: "div", children: [child])
      expect(node.element?).to be true
    end

    it "returns true for node with attributes" do
      node = described_class.new(label: "div", attributes: { "class" => "test" })
      expect(node.element?).to be true
    end

    it "returns false for simple leaf node" do
      node = described_class.new(label: "text", value: "Hello")
      expect(node.element?).to be false
    end
  end

  describe "#root" do
    it "returns self for root node" do
      node = described_class.new(label: "root")
      expect(node.root).to eq(node)
    end

    it "returns root for nested node" do
      root = described_class.new(label: "root")
      child = described_class.new(label: "child", parent: root)
      grandchild = described_class.new(label: "grandchild", parent: child)

      root.children = [child]
      child.children = [grandchild]

      expect(grandchild.root).to eq(root)
    end
  end

  describe "#ancestors" do
    it "returns empty array for root node" do
      node = described_class.new(label: "root")
      expect(node.ancestors).to eq([])
    end

    it "returns ancestors from parent to root" do
      root = described_class.new(label: "root")
      child = described_class.new(label: "child", parent: root)
      grandchild = described_class.new(label: "grandchild", parent: child)

      root.children = [child]
      child.children = [grandchild]

      expect(grandchild.ancestors).to eq([child, root])
    end
  end

  describe "#descendants" do
    it "returns empty array for leaf node" do
      node = described_class.new(label: "leaf")
      expect(node.descendants).to eq([])
    end

    it "returns all descendants depth-first" do
      root = described_class.new(label: "root")
      child1 = described_class.new(label: "child1")
      child2 = described_class.new(label: "child2")
      grandchild1 = described_class.new(label: "grandchild1")
      grandchild2 = described_class.new(label: "grandchild2")

      root.add_child(child1)
      root.add_child(child2)
      child1.add_child(grandchild1)
      child1.add_child(grandchild2)

      descendants = root.descendants
      expect(descendants).to eq([child1, grandchild1, grandchild2, child2])
    end
  end

  describe "#siblings" do
    it "returns empty array for root node" do
      node = described_class.new(label: "root")
      expect(node.siblings).to eq([])
    end

    it "returns sibling nodes" do
      parent = described_class.new(label: "parent")
      child1 = described_class.new(label: "child1")
      child2 = described_class.new(label: "child2")
      child3 = described_class.new(label: "child3")

      parent.add_child(child1)
      parent.add_child(child2)
      parent.add_child(child3)

      expect(child2.siblings).to contain_exactly(child1, child3)
    end
  end

  describe "#left_siblings" do
    it "returns siblings before this node" do
      parent = described_class.new(label: "parent")
      child1 = described_class.new(label: "child1")
      child2 = described_class.new(label: "child2")
      child3 = described_class.new(label: "child3")

      parent.add_child(child1)
      parent.add_child(child2)
      parent.add_child(child3)

      expect(child3.left_siblings).to eq([child1, child2])
    end

    it "returns empty array for first child" do
      parent = described_class.new(label: "parent")
      child1 = described_class.new(label: "child1")
      child2 = described_class.new(label: "child2")

      parent.add_child(child1)
      parent.add_child(child2)

      expect(child1.left_siblings).to eq([])
    end
  end

  describe "#right_siblings" do
    it "returns siblings after this node" do
      parent = described_class.new(label: "parent")
      child1 = described_class.new(label: "child1")
      child2 = described_class.new(label: "child2")
      child3 = described_class.new(label: "child3")

      parent.add_child(child1)
      parent.add_child(child2)
      parent.add_child(child3)

      expect(child1.right_siblings).to eq([child2, child3])
    end

    it "returns empty array for last child" do
      parent = described_class.new(label: "parent")
      child1 = described_class.new(label: "child1")
      child2 = described_class.new(label: "child2")

      parent.add_child(child1)
      parent.add_child(child2)

      expect(child2.right_siblings).to eq([])
    end
  end

  describe "#position" do
    it "returns nil for root node" do
      node = described_class.new(label: "root")
      expect(node.position).to be_nil
    end

    it "returns position among siblings" do
      parent = described_class.new(label: "parent")
      child1 = described_class.new(label: "child1")
      child2 = described_class.new(label: "child2")
      child3 = described_class.new(label: "child3")

      parent.add_child(child1)
      parent.add_child(child2)
      parent.add_child(child3)

      expect(child1.position).to eq(0)
      expect(child2.position).to eq(1)
      expect(child3.position).to eq(2)
    end
  end

  describe "#depth" do
    it "returns 0 for root node" do
      node = described_class.new(label: "root")
      expect(node.depth).to eq(0)
    end

    it "returns depth from root" do
      root = described_class.new(label: "root")
      child = described_class.new(label: "child")
      grandchild = described_class.new(label: "grandchild")

      root.add_child(child)
      child.add_child(grandchild)

      expect(child.depth).to eq(1)
      expect(grandchild.depth).to eq(2)
    end
  end

  describe "#height" do
    it "returns 0 for leaf node" do
      node = described_class.new(label: "leaf")
      expect(node.height).to eq(0)
    end

    it "returns height of tree" do
      root = described_class.new(label: "root")
      child1 = described_class.new(label: "child1")
      child2 = described_class.new(label: "child2")
      grandchild = described_class.new(label: "grandchild")

      root.add_child(child1)
      root.add_child(child2)
      child1.add_child(grandchild)

      expect(root.height).to eq(2)
      expect(child1.height).to eq(1)
      expect(child2.height).to eq(0)
    end
  end

  describe "#size" do
    it "returns 1 for leaf node" do
      node = described_class.new(label: "leaf")
      expect(node.size).to eq(1)
    end

    it "returns size of subtree" do
      root = described_class.new(label: "root")
      child1 = described_class.new(label: "child1")
      child2 = described_class.new(label: "child2")
      grandchild = described_class.new(label: "grandchild")

      root.add_child(child1)
      root.add_child(child2)
      child1.add_child(grandchild)

      expect(root.size).to eq(4)
      expect(child1.size).to eq(2)
      expect(child2.size).to eq(1)
    end
  end

  describe "#add_child" do
    it "adds child to children array" do
      parent = described_class.new(label: "parent")
      child = described_class.new(label: "child")

      parent.add_child(child)

      expect(parent.children).to eq([child])
      expect(child.parent).to eq(parent)
    end

    it "adds child at specific position" do
      parent = described_class.new(label: "parent")
      child1 = described_class.new(label: "child1")
      child2 = described_class.new(label: "child2")
      child3 = described_class.new(label: "child3")

      parent.add_child(child1)
      parent.add_child(child3)
      parent.add_child(child2, position: 1)

      expect(parent.children).to eq([child1, child2, child3])
    end

    it "invalidates cached computations" do
      parent = described_class.new(label: "parent")
      parent.signature = "cached"
      parent.weight = "cached"

      child = described_class.new(label: "child")
      parent.add_child(child)

      expect(parent.signature).to be_nil
      expect(parent.weight).to be_nil
    end
  end

  describe "#remove_child" do
    it "removes child from children array" do
      parent = described_class.new(label: "parent")
      child = described_class.new(label: "child")

      parent.add_child(child)
      removed = parent.remove_child(child)

      expect(parent.children).to eq([])
      expect(removed).to eq(child)
      expect(child.parent).to be_nil
    end

    it "returns nil if child not found" do
      parent = described_class.new(label: "parent")
      other = described_class.new(label: "other")

      result = parent.remove_child(other)

      expect(result).to be_nil
    end
  end

  describe "#replace_child" do
    it "replaces old child with new child" do
      parent = described_class.new(label: "parent")
      old_child = described_class.new(label: "old")
      new_child = described_class.new(label: "new")

      parent.add_child(old_child)
      replaced = parent.replace_child(old_child, new_child)

      expect(parent.children).to eq([new_child])
      expect(replaced).to eq(old_child)
      expect(old_child.parent).to be_nil
      expect(new_child.parent).to eq(parent)
    end

    it "returns nil if old child not found" do
      parent = described_class.new(label: "parent")
      old_child = described_class.new(label: "old")
      new_child = described_class.new(label: "new")

      result = parent.replace_child(old_child, new_child)

      expect(result).to be_nil
    end
  end

  describe "#matches?" do
    it "returns true for identical nodes" do
      node1 = described_class.new(
        label: "div",
        value: "text",
        attributes: { "class" => "test" }
      )
      node2 = described_class.new(
        label: "div",
        value: "text",
        attributes: { "class" => "test" }
      )

      expect(node1.matches?(node2)).to be true
    end

    it "returns false for different labels" do
      node1 = described_class.new(label: "div")
      node2 = described_class.new(label: "span")

      expect(node1.matches?(node2)).to be false
    end

    it "returns false for different values" do
      node1 = described_class.new(label: "text", value: "Hello")
      node2 = described_class.new(label: "text", value: "World")

      expect(node1.matches?(node2)).to be false
    end

    it "returns false for different attributes" do
      node1 = described_class.new(label: "div", attributes: { "class" => "a" })
      node2 = described_class.new(label: "div", attributes: { "class" => "b" })

      expect(node1.matches?(node2)).to be false
    end

    it "checks children count and labels" do
      child1a = described_class.new(label: "span")
      child1b = described_class.new(label: "p")
      node1 = described_class.new(label: "div", children: [child1a, child1b])

      child2a = described_class.new(label: "span")
      child2b = described_class.new(label: "p")
      node2 = described_class.new(label: "div", children: [child2a, child2b])

      expect(node1.matches?(node2)).to be true
    end
  end

  describe "#similarity_to" do
    it "returns 1.0 for identical nodes" do
      node1 = described_class.new(
        label: "div",
        value: "text",
        attributes: { "class" => "test" }
      )
      node2 = described_class.new(
        label: "div",
        value: "text",
        attributes: { "class" => "test" }
      )

      expect(node1.similarity_to(node2)).to eq(1.0)
    end

    it "returns 0.0 for completely different nodes" do
      node1 = described_class.new(label: "div", value: "a")
      node2 = described_class.new(label: "span", value: "b")

      similarity = node1.similarity_to(node2)
      expect(similarity).to be < 0.5
    end

    it "returns intermediate value for partially similar nodes" do
      node1 = described_class.new(
        label: "div",
        value: "text",
        attributes: { "class" => "a" }
      )
      node2 = described_class.new(
        label: "div",
        value: "text",
        attributes: { "class" => "b" }
      )

      similarity = node1.similarity_to(node2)
      expect(similarity).to be >= 0.5
      expect(similarity).to be < 1.0
    end
  end

  describe "#semantic_distance_to" do
    it "returns 0 for identical nodes at same depth" do
      node1 = described_class.new(label: "div", value: "text")
      node2 = described_class.new(label: "div", value: "text")

      expect(node1.semantic_distance_to(node2)).to eq(0.0)
    end

    it "increases with depth difference" do
      root = described_class.new(label: "root")
      child = described_class.new(label: "child")
      grandchild = described_class.new(label: "grandchild")

      root.add_child(child)
      child.add_child(grandchild)

      node1 = described_class.new(label: "div")
      node2 = described_class.new(label: "div")

      # Same depth: distance should be lower
      dist_same = node1.semantic_distance_to(node2)

      # Different depth: distance should be higher
      root.add_child(node1)
      child.add_child(node2)
      dist_diff = node1.semantic_distance_to(node2)

      expect(dist_diff).to be > dist_same
    end

    it "increases with content dissimilarity" do
      node1 = described_class.new(label: "div", value: "same")
      node2 = described_class.new(label: "div", value: "same")
      node3 = described_class.new(label: "span", value: "different")

      dist_similar = node1.semantic_distance_to(node2)
      dist_different = node1.semantic_distance_to(node3)

      expect(dist_different).to be > dist_similar
    end
  end

  describe "#deep_clone" do
    it "creates independent copy of node" do
      original = described_class.new(
        label: "div",
        value: "text",
        attributes: { "class" => "test" },
        xid: "id123"
      )

      clone = original.deep_clone

      expect(clone.label).to eq(original.label)
      expect(clone.value).to eq(original.value)
      expect(clone.attributes).to eq(original.attributes)
      expect(clone.xid).to eq(original.xid)
      expect(clone.parent).to be_nil
    end

    it "deep clones entire subtree" do
      root = described_class.new(label: "root")
      child = described_class.new(label: "child")
      grandchild = described_class.new(label: "grandchild")

      root.add_child(child)
      child.add_child(grandchild)

      clone = root.deep_clone

      expect(clone.children.size).to eq(1)
      expect(clone.children[0].label).to eq("child")
      expect(clone.children[0].children[0].label).to eq("grandchild")
      expect(clone.children[0].parent).to eq(clone)
    end
  end

  describe "#to_h" do
    it "converts node to hash representation" do
      node = described_class.new(
        label: "div",
        value: "text",
        attributes: { "class" => "test" },
        xid: "id123"
      )

      hash = node.to_h

      expect(hash[:label]).to eq("div")
      expect(hash[:value]).to eq("text")
      expect(hash[:attributes]).to eq({ "class" => "test" })
      expect(hash[:xid]).to eq("id123")
      expect(hash[:children]).to eq([])
    end

    it "includes signature and weight if set" do
      node = described_class.new(label: "div")
      node.signature = "test-signature"
      node.weight = 42.0

      hash = node.to_h

      expect(hash[:signature]).to eq("test-signature")
      expect(hash[:weight]).to eq(42.0)
    end

    it "converts children recursively" do
      root = described_class.new(label: "root")
      child = described_class.new(label: "child")
      root.add_child(child)

      hash = root.to_h

      expect(hash[:children].size).to eq(1)
      expect(hash[:children][0][:label]).to eq("child")
    end
  end
end
