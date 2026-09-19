# frozen_string_literal: true

module Canon
  module TreeDiff
    module Core
      # NodeSignature computes unique signatures for tree nodes
      #
      # Based on XDiff (2002, U. Wisconsin) approach:
      # - Signature is the path from root to node
      # - Format: /ancestor1/ancestor2/.../node/type
      # - Used for fast exact matching via hash lookup
      #
      # Features:
      # - Deterministic: Same path always produces same signature
      # - Hierarchical: Parent-child relationships encoded
      # - Type-aware: Distinguishes element vs text nodes
      class NodeSignature
        attr_reader :path, :signature_string

        # Initialize signature for a node
        #
        # @param node [TreeNode] Node to compute signature for
        # @param include_attributes [Boolean] Whether to include attributes
        def initialize(node, include_attributes: true)
          @node = node
          @include_attributes = include_attributes
          @path = compute_path
          @signature_string = compute_signature_string
        end

        # Compute and cache signature for a node
        #
        # @param node [TreeNode] Node to compute signature for
        # @param include_attributes [Boolean] Whether to include attributes in signature
        # @return [NodeSignature]
        def self.for(node, include_attributes: true)
          if include_attributes
            node.signature ||= new(node, include_attributes: true)
          else
            # Don't cache loose signatures
            new(node, include_attributes: false)
          end
        end

        # Check if two signatures are equal
        #
        # @param other [NodeSignature] Signature to compare with
        # @return [Boolean]
        def ==(other)
          return false unless other.is_a?(NodeSignature)

          signature_string == other.signature_string
        end

        alias eql? ==

        # Hash value for use in Hash/Set
        #
        # @return [Integer]
        def hash
          signature_string.hash
        end

        # String representation
        #
        # @return [String]
        def to_s
          signature_string
        end

        # Detailed inspection
        #
        # @return [String]
        def inspect
          "#<NodeSignature #{signature_string.inspect}>"
        end

        private

        # Compute the path from root to this node
        #
        # @return [Array<String>] Path components
        def compute_path
          @node.signature_path(include_attributes: @include_attributes)
        end

        # Compute signature string from path
        #
        # @return [String]
        def compute_signature_string
          "/#{path.join('/')}"
        end
      end
    end
  end
end
