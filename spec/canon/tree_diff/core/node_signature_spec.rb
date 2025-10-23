# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/canon/tree_diff/core/tree_node"
require_relative "../../../../lib/canon/tree_diff/core/node_signature"

RSpec.describe Canon::TreeDiff::Core::NodeSignature do
  let(:tree_node_class) { Canon::TreeDiff::Core::TreeNode }

  describe "#initialize" do
    it "computes signature for simple node" do
      node = tree_node_class.new(label: "div")
      signature = described_class.new(node)

      expect(signature.signature_string).to eq("/div")
    end

    it "computes signature with ancestor path" do
      root = tree_node_class.new(label: "root")
      child = tree_node_class.new(label: "child")
      grandchild = tree_node_class.new(label: "grandchild")

      root.add_child(child)
      child.add_child(grandchild)

      signature = described_class.new(grandchild)

      expect(signature.signature_string).to eq("/root/child/grandchild")
    end

    it "uses #text for text nodes" do
      parent = tree_node_class.new(label: "p")
      text_node = tree_node_class.new(label: "text", value: "Hello World")
      parent.add_child(text_node)

      signature = described_class.new(text_node)

      expect(signature.signature_string).to eq("/p/#text")
    end

    it "distinguishes element from text nodes" do
      parent = tree_node_class.new(label: "div")
      element = tree_node_class.new(label: "span")
      text = tree_node_class.new(label: "text", value: "content")

      parent.add_child(element)
      parent.add_child(text)

      element_sig = described_class.new(element)
      text_sig = described_class.new(text)

      expect(element_sig.signature_string).to eq("/div/span")
      expect(text_sig.signature_string).to eq("/div/#text")
    end
  end

  describe ".for" do
    it "computes and caches signature on node" do
      node = tree_node_class.new(label: "div")

      signature1 = described_class.for(node)
      signature2 = described_class.for(node)

      expect(signature1).to be(signature2)
      expect(node.signature).to eq(signature1)
    end

    it "returns cached signature if already computed" do
      node = tree_node_class.new(label: "div")
      cached = described_class.new(node)
      node.signature = cached

      result = described_class.for(node)

      expect(result).to be(cached)
    end
  end

  describe "#==" do
    it "returns true for same signature strings" do
      node1 = tree_node_class.new(label: "div")
      node2 = tree_node_class.new(label: "div")

      sig1 = described_class.new(node1)
      sig2 = described_class.new(node2)

      expect(sig1).to eq(sig2)
    end

    it "returns false for different signature strings" do
      node1 = tree_node_class.new(label: "div")
      node2 = tree_node_class.new(label: "span")

      sig1 = described_class.new(node1)
      sig2 = described_class.new(node2)

      expect(sig1).not_to eq(sig2)
    end

    it "returns false for different paths" do
      root1 = tree_node_class.new(label: "root")
      child1 = tree_node_class.new(label: "child")
      root1.add_child(child1)

      root2 = tree_node_class.new(label: "other")
      child2 = tree_node_class.new(label: "child")
      root2.add_child(child2)

      sig1 = described_class.new(child1)
      sig2 = described_class.new(child2)

      expect(sig1).not_to eq(sig2)
    end
  end

  describe "#hash" do
    it "returns same hash for equal signatures" do
      node1 = tree_node_class.new(label: "div")
      node2 = tree_node_class.new(label: "div")

      sig1 = described_class.new(node1)
      sig2 = described_class.new(node2)

      expect(sig1.hash).to eq(sig2.hash)
    end

    it "allows use in Hash/Set" do
      node1 = tree_node_class.new(label: "div")
      node2 = tree_node_class.new(label: "div")
      node3 = tree_node_class.new(label: "span")

      sig1 = described_class.new(node1)
      sig2 = described_class.new(node2)
      sig3 = described_class.new(node3)

      hash_map = { sig1 => "value1" }
      hash_map[sig3] = "value3"

      # sig2 should find sig1's value (same signature)
      expect(hash_map[sig2]).to eq("value1")
      expect(hash_map[sig3]).to eq("value3")
    end
  end

  describe "#to_s" do
    it "returns signature string" do
      node = tree_node_class.new(label: "div")
      signature = described_class.new(node)

      expect(signature.to_s).to eq("/div")
    end
  end

  describe "path computation" do
    it "includes all ancestors in order" do
      root = tree_node_class.new(label: "html")
      body = tree_node_class.new(label: "body")
      div = tree_node_class.new(label: "div")
      p = tree_node_class.new(label: "p")

      root.add_child(body)
      body.add_child(div)
      div.add_child(p)

      signature = described_class.new(p)

      expect(signature.signature_string).to eq("/html/body/div/p")
    end

    it "handles single root node" do
      node = tree_node_class.new(label: "root")
      signature = described_class.new(node)

      expect(signature.signature_string).to eq("/root")
    end
  end
end
