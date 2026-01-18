# frozen_string_literal: true

require_relative "../../diff/path_builder"
require_relative "../../diff/node_serializer"

module Canon
  module TreeDiff
    module OperationConverterHelpers
      # Metadata enrichment for DiffNodes
      # Handles path building, serialization, and attribute extraction
      module MetadataEnricher
        # Enrich DiffNode with canonical path, serialized content, and attributes
        # This extracts presentation-ready metadata from TreeNodes for Stage 4 rendering
        #
        # @param tree_node1 [Canon::TreeDiff::Core::TreeNode, nil] First tree node
        # @param tree_node2 [Canon::TreeDiff::Core::TreeNode, nil] Second tree node
        # @param format [Symbol] Document format
        # @return [Hash] Enriched metadata hash
        def self.enrich(tree_node1, tree_node2, format)
          {
            path: build_path(tree_node1 || tree_node2, format),
            serialized_before: serialize(tree_node1),
            serialized_after: serialize(tree_node2),
            attributes_before: extract_attributes(tree_node1),
            attributes_after: extract_attributes(tree_node2),
          }
        end

        # Build canonical path for a TreeNode
        #
        # @param tree_node [Canon::TreeDiff::Core::TreeNode] Tree node
        # @param format [Symbol] Document format
        # @return [String, nil] Canonical path with ordinal indices
        def self.build_path(tree_node, format)
          return nil if tree_node.nil?

          Canon::Diff::PathBuilder.build(tree_node,
                                         format: format == :xml ? :document : :fragment)
        end

        # Serialize a TreeNode's source node to string
        #
        # @param tree_node [Canon::TreeDiff::Core::TreeNode, nil] Tree node
        # @return [String, nil] Serialized content
        def self.serialize(tree_node)
          return nil if tree_node.nil?

          # Extract source node from TreeNode
          source = if tree_node.respond_to?(:source_node)
                     tree_node.source_node
                   else
                     tree_node
                   end

          Canon::Diff::NodeSerializer.serialize(source)
        end

        # Extract attributes from a TreeNode
        #
        # @param tree_node [Canon::TreeDiff::Core::TreeNode, nil] Tree node
        # @return [Hash, nil] Attributes hash
        def self.extract_attributes(tree_node)
          return nil if tree_node.nil?

          # Use TreeNode's attributes directly (already normalized by adapter)
          tree_node.respond_to?(:attributes) ? (tree_node.attributes || {}) : {}
        end
      end
    end
  end
end
