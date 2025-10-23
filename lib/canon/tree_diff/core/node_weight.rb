# frozen_string_literal: true

module Canon
  module TreeDiff
    module Core
      # NodeWeight computes weights for tree nodes
      #
      # Based on XyDiff/Cobena (2002, INRIA) approach:
      # - Weight reflects subtree size/importance
      # - Formula: 1 + Σ(child_weights)
      # - Text nodes: 1 + log(text_length) for significant text
      # - Used to prioritize matching (heaviest first)
      #
      # Features:
      # - Hierarchical: Parent weight includes all descendants
      # - Text-aware: Longer text has higher weight
      # - Cached: Computed once and reused
      class NodeWeight
        attr_reader :value

        # Initialize weight for a node
        #
        # @param node [TreeNode] Node to compute weight for
        def initialize(node)
          @node = node
          @value = compute_weight
        end

        # Compute and cache weight for a node
        #
        # @param node [TreeNode] Node to compute weight for
        # @return [NodeWeight]
        def self.for(node)
          node.weight ||= new(node)
        end

        # Compare weights (for sorting)
        #
        # @param other [NodeWeight] Weight to compare with
        # @return [Integer] -1, 0, or 1
        def <=>(other)
          return nil unless other.is_a?(NodeWeight)

          value <=> other.value
        end

        # Check if equal
        #
        # @param other [NodeWeight] Weight to compare with
        # @return [Boolean]
        def ==(other)
          return false unless other.is_a?(NodeWeight)

          value == other.value
        end

        # Numeric value for calculations
        #
        # @return [Float]
        def to_f
          value
        end

        # Integer value for calculations
        #
        # @return [Integer]
        def to_i
          value.to_i
        end

        # String representation
        #
        # @return [String]
        def to_s
          value.to_s
        end

        # Detailed inspection
        #
        # @return [String]
        def inspect
          "#<NodeWeight #{value}>"
        end

        private

        # Compute weight based on node type and structure
        #
        # @return [Float]
        def compute_weight
          if @node.text?
            compute_text_weight
          else
            compute_element_weight
          end
        end

        # Compute weight for text nodes
        #
        # Formula: 1 + log(text_length)
        # - Minimum weight is 1.0 (empty text)
        # - Grows logarithmically with text length
        # - Prevents very long text from dominating
        #
        # @return [Float]
        def compute_text_weight
          text = @node.value.to_s
          return 1.0 if text.empty?

          # Use natural logarithm (log base e)
          # Add 1 to avoid log(0)
          1.0 + Math.log(text.length + 1)
        end

        # Compute weight for element nodes
        #
        # Formula: 1 + Σ(child_weights)
        # - Each node has base weight of 1
        # - Parent weight includes all descendants
        # - Recursive computation
        #
        # @return [Float]
        def compute_element_weight
          return 1.0 if @node.children.empty?

          child_weights = @node.children.map do |child|
            self.class.for(child).value
          end

          1.0 + child_weights.sum
        end
      end
    end
  end
end
