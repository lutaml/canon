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
          components = []

          # Build path from root to node
          ancestors = @node.ancestors.reverse
          ancestors.each do |ancestor|
            components << path_component(ancestor)
          end

          # Add the node itself
          components << path_component(@node)

          components
        end

        # Get path component for a node
        #
        # @param node [TreeNode] Node to get component for
        # @return [String]
        def path_component(node)
          # For element nodes: use label with sorted attributes
          # For text nodes: use "#text"
          # CRITICAL: Don't use node.text? which is true for ANY leaf with value
          # Check the label instead - actual text nodes have no label or special markers
          if node.label.nil? || node.label.to_s.empty? || node.label == "#text"
            "#text"
          else
            component = node.label.to_s

            # Include sorted attributes to distinguish nodes with same label
            # but different attributes (while ignoring attribute order)
            # Only include attributes if requested (for hash matching)
            if @include_attributes && !node.attributes.empty?
              sorted_attrs = node.attributes.sort.to_h
              attrs_str = sorted_attrs.map { |k, v| "#{k}=#{v}" }.join(",")
              component += "{#{attrs_str}}"
            end

            # CRITICAL: For whitespace-sensitive HTML elements, include the text value
            # in the signature to prevent incorrect matching of nodes with different whitespace
            if @include_attributes && whitespace_sensitive?(node) && node.value
              # Include text value in signature for whitespace-sensitive elements
              # Use inspect to make whitespace visible and handle special characters
              component += "[text=#{node.value.inspect}]"
            end

            component
          end
        end

        # Check if a node is in a whitespace-sensitive context
        #
        # HTML elements where whitespace is significant: <pre>, <code>, <textarea>, <script>, <style>
        #
        # @param node [TreeNode] Node to check
        # @return [Boolean] True if node is whitespace-sensitive
        def whitespace_sensitive?(node)
          return false unless node

          # List of HTML elements where whitespace is semantically significant
          whitespace_sensitive_tags = %w[pre code textarea script style]

          # Check if this node is whitespace-sensitive
          if node.respond_to?(:label)
            label = node.label.to_s.downcase
            return true if whitespace_sensitive_tags.include?(label)
          end

          false
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
