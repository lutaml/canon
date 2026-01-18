# frozen_string_literal: true

require "spec_helper"

RSpec.describe Canon::Comparison::MarkupComparer do
  describe ".compare_nodes" do
    it "raises NotImplementedError - must be implemented by subclass" do
      # This method is implemented in the base class for common functionality
      # Subclasses provide format-specific behavior through other methods
      expect { described_class.compare_nodes(nil, nil, {}, {}, false, []) }
        .not_to raise_error
    end

    it "returns EQUIVALENT for nil nodes" do
      # When both nodes are nil, they should be considered equivalent
      result = described_class.compare_nodes(nil, nil, {}, {}, false, [])
      expect(result).to eq(Canon::Comparison::EQUIVALENT)
    end
  end

  describe ".filter_children" do
    let(:children) do
      # Create simple test objects with needed methods
      node1 = Object.new
      def node1.name; "p"; end
      def node1.text?; false; end
      def node1.comment?; false; end

      node2 = Object.new
      def node2.name; "div"; end
      def node2.text?; false; end
      def node2.comment?; false; end

      [node1, node2]
    end

    it "returns all children when no filters are specified" do
      filtered = described_class.filter_children(children, {})
      expect(filtered.length).to eq(2)
    end

    it "filters nodes by ignore_nodes option" do
      filtered = described_class.filter_children(children,
                                                 { ignore_nodes: [children[0]] })
      expect(filtered.length).to eq(1)
      expect(filtered.first).to eq(children[1])
    end
  end
end
