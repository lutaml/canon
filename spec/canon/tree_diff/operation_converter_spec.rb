# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::TreeDiff::OperationConverter do
  let(:format) { :xml }
  let(:match_options) { {} }
  let(:converter) do
    described_class.new(format: format, match_options: match_options)
  end

  describe "#initialize" do
    it "creates converter with format and match options" do
      expect(converter.format).to eq(:xml)
      expect(converter.match_options).to be_a(Canon::Comparison::ResolvedMatchOptions)
    end
  end

  describe "#convert" do
    context "with INSERT operations" do
      it "converts insert operation to DiffNode" do
        # Create a mock operation
        node = double("TreeNode", label: "div", source_node: double("Node"))
        operation = Canon::TreeDiff::Operations::Operation.new(
          type: :insert,
          node: node,
        )

        diff_nodes = converter.convert([operation])

        expect(diff_nodes.size).to eq(1)
        expect(diff_nodes.first).to be_a(Canon::Diff::DiffNode)
        expect(diff_nodes.first.node1).to be_nil
        expect(diff_nodes.first.node2).to eq(node.source_node)
        expect(diff_nodes.first.dimension).to eq(:element_structure)
        expect(diff_nodes.first.reason).to include("inserted")
        expect(diff_nodes.first.normative?).to be true
      end
    end

    context "with DELETE operations" do
      it "converts delete operation to DiffNode" do
        node = double("TreeNode", label: "span", source_node: double("Node"))
        operation = Canon::TreeDiff::Operations::Operation.new(
          type: :delete,
          node: node,
        )

        diff_nodes = converter.convert([operation])

        expect(diff_nodes.size).to eq(1)
        expect(diff_nodes.first.node1).to eq(node.source_node)
        expect(diff_nodes.first.node2).to be_nil
        expect(diff_nodes.first.dimension).to eq(:element_structure)
        expect(diff_nodes.first.reason).to include("deleted")
        expect(diff_nodes.first.normative?).to be true
      end
    end

    context "with UPDATE operations" do
      it "converts text content update to DiffNode" do
        node1 = double("TreeNode", source_node: double("Node1"))
        node2 = double("TreeNode", source_node: double("Node2"))
        operation = Canon::TreeDiff::Operations::Operation.new(
          type: :update,
          node1: node1,
          node2: node2,
          changes: { value: true },
        )

        diff_nodes = converter.convert([operation])

        expect(diff_nodes.first.dimension).to eq(:text_content)
        expect(diff_nodes.first.reason).to eq("text content differs")
      end

      it "converts attribute update to DiffNode" do
        node1 = double("TreeNode", source_node: double("Node1"))
        node2 = double("TreeNode", source_node: double("Node2"))
        operation = Canon::TreeDiff::Operations::Operation.new(
          type: :update,
          node1: node1,
          node2: node2,
          changes: { attributes: true },
        )

        diff_nodes = converter.convert([operation])

        expect(diff_nodes.first.dimension).to eq(:attribute_values)
        expect(diff_nodes.first.reason).to eq("attribute values differ")
      end

      it "converts attribute order update to DiffNode" do
        node1 = double("TreeNode", source_node: double("Node1"))
        node2 = double("TreeNode", source_node: double("Node2"))
        operation = Canon::TreeDiff::Operations::Operation.new(
          type: :update,
          node1: node1,
          node2: node2,
          changes: { attribute_order: true },
        )

        diff_nodes = converter.convert([operation])

        expect(diff_nodes.first.dimension).to eq(:attribute_order)
        expect(diff_nodes.first.reason).to eq("attribute order differs")
      end

      it "defaults to text_content for generic updates" do
        node1 = double("TreeNode", source_node: double("Node1"))
        node2 = double("TreeNode", source_node: double("Node2"))
        operation = Canon::TreeDiff::Operations::Operation.new(
          type: :update,
          node1: node1,
          node2: node2,
        )

        diff_nodes = converter.convert([operation])

        expect(diff_nodes.first.dimension).to eq(:text_content)
      end
    end

    context "with MOVE operations" do
      it "converts move operation to DiffNode" do
        node1 = double("TreeNode", source_node: double("Node1"))
        node2 = double("TreeNode", source_node: double("Node2"))
        operation = Canon::TreeDiff::Operations::Operation.new(
          type: :move,
          node1: node1,
          node2: node2,
          from_position: 2,
          to_position: 5,
        )

        diff_nodes = converter.convert([operation])

        expect(diff_nodes.first.dimension).to eq(:element_position)
        expect(diff_nodes.first.reason).to include("moved")
        expect(diff_nodes.first.reason).to include("2")
        expect(diff_nodes.first.reason).to include("5")
      end
    end

    context "with MERGE operations" do
      it "converts merge operation to DiffNode" do
        nodes = [
          double("TreeNode", source_node: double("Node1")),
          double("TreeNode", source_node: double("Node2")),
        ]
        result = double("TreeNode", source_node: double("ResultNode"))
        operation = Canon::TreeDiff::Operations::Operation.new(
          type: :merge,
          nodes: nodes,
          result: result,
        )

        diff_nodes = converter.convert([operation])

        expect(diff_nodes.first.dimension).to eq(:element_structure)
        expect(diff_nodes.first.reason).to include("merged")
        expect(diff_nodes.first.normative?).to be true
      end
    end

    context "with SPLIT operations" do
      it "converts split operation to DiffNode" do
        node = double("TreeNode", source_node: double("Node"))
        results = [
          double("TreeNode", source_node: double("Result1")),
          double("TreeNode", source_node: double("Result2")),
        ]
        operation = Canon::TreeDiff::Operations::Operation.new(
          type: :split,
          node: node,
          results: results,
        )

        diff_nodes = converter.convert([operation])

        expect(diff_nodes.first.dimension).to eq(:element_structure)
        expect(diff_nodes.first.reason).to include("split")
        expect(diff_nodes.first.normative?).to be true
      end
    end

    context "with UPGRADE operations" do
      it "converts upgrade (promote) operation to DiffNode" do
        node1 = double("TreeNode", source_node: double("Node1"))
        node2 = double("TreeNode", source_node: double("Node2"))
        operation = Canon::TreeDiff::Operations::Operation.new(
          type: :upgrade,
          node1: node1,
          node2: node2,
        )

        diff_nodes = converter.convert([operation])

        expect(diff_nodes.first.dimension).to eq(:element_hierarchy)
        expect(diff_nodes.first.reason).to include("promoted")
      end
    end

    context "with DOWNGRADE operations" do
      it "converts downgrade (demote) operation to DiffNode" do
        node1 = double("TreeNode", source_node: double("Node1"))
        node2 = double("TreeNode", source_node: double("Node2"))
        operation = Canon::TreeDiff::Operations::Operation.new(
          type: :downgrade,
          node1: node1,
          node2: node2,
        )

        diff_nodes = converter.convert([operation])

        expect(diff_nodes.first.dimension).to eq(:element_hierarchy)
        expect(diff_nodes.first.reason).to include("demoted")
      end
    end

    context "with multiple operations" do
      it "converts all operations in order" do
        insert_node = double("TreeNode", label: "div",
                                         source_node: double("InsertNode"))
        delete_node = double("TreeNode", label: "span",
                                         source_node: double("DeleteNode"))

        operations = [
          Canon::TreeDiff::Operations::Operation.new(type: :insert,
                                                     node: insert_node),
          Canon::TreeDiff::Operations::Operation.new(type: :delete,
                                                     node: delete_node),
        ]

        diff_nodes = converter.convert(operations)

        expect(diff_nodes.size).to eq(2)
        expect(diff_nodes[0].dimension).to eq(:element_structure)
        expect(diff_nodes[0].reason).to include("inserted")
        expect(diff_nodes[1].dimension).to eq(:element_structure)
        expect(diff_nodes[1].reason).to include("deleted")
      end
    end

    context "with match options" do
      let(:match_options) { { element_position: :ignore } }

      it "applies match options to determine normative status" do
        node1 = double("TreeNode", source_node: double("Node1"))
        node2 = double("TreeNode", source_node: double("Node2"))
        operation = Canon::TreeDiff::Operations::Operation.new(
          type: :move,
          node1: node1,
          node2: node2,
        )

        diff_nodes = converter.convert([operation])

        # Since element_position is :ignore, move should be informative
        expect(diff_nodes.first.normative?).to be false
      end
    end
  end

  describe "source node extraction" do
    it "extracts source_node from TreeNode wrapper" do
      source = double("SourceNode")
      tree_node = double("TreeNode", source_node: source, label: "div")
      operation = Canon::TreeDiff::Operations::Operation.new(
        type: :insert,
        node: tree_node,
      )

      diff_nodes = converter.convert([operation])

      expect(diff_nodes.first.node2).to eq(source)
    end

    it "handles nil nodes" do
      operation = Canon::TreeDiff::Operations::Operation.new(
        type: :insert,
        node: nil,
      )

      diff_nodes = converter.convert([operation])

      expect(diff_nodes.first.node2).to be_nil
    end

    it "returns node as-is if not a TreeNode" do
      raw_node = double("RawNode")
      operation = Canon::TreeDiff::Operations::Operation.new(
        type: :insert,
        node: raw_node,
      )

      diff_nodes = converter.convert([operation])

      expect(diff_nodes.first.node2).to eq(raw_node)
    end
  end

  describe "error handling" do
    it "raises ArgumentError for unknown operation type" do
      # This shouldn't happen in practice since Operation validates types
      # But test the converter's handling
      operation = double("Operation", type: :unknown_type, metadata: {})

      expect do
        converter.send(:convert_operation, operation)
      end.to raise_error(ArgumentError, /Unknown operation type/)
    end
  end
end
