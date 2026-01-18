# frozen_string_literal: true

require_relative "../../diff/diff_node"
require_relative "../../diff/path_builder"
require_relative "../../diff/node_serializer"

module Canon
  module Comparison
    # Builder for creating enriched DiffNode objects
    # Handles path building, serialization, and attribute extraction
    class DiffNodeBuilder
      # Build an enriched DiffNode
      #
      # @param node1 [Object, nil] First node
      # @param node2 [Object, nil] Second node
      # @param diff1 [String] Difference type for node1
      # @param diff2 [String] Difference type for node2
      # @param dimension [Symbol] The match dimension causing this difference
      # @return [DiffNode, nil] Enriched DiffNode or nil if dimension is nil
      def self.build(node1:, node2:, diff1:, diff2:, dimension:, **_opts)
        # Validate dimension is required
        if dimension.nil?
          raise ArgumentError,
                "dimension required for DiffNode"
        end

        # Build informative reason message
        reason = build_reason(node1, node2, diff1, diff2, dimension)

        # Enrich with path, serialized content, and attributes for Stage 4 rendering
        metadata = enrich_metadata(node1, node2)

        Canon::Diff::DiffNode.new(
          node1: node1,
          node2: node2,
          dimension: dimension,
          reason: reason,
          **metadata,
        )
      end

      # Build a human-readable reason for a difference
      #
      # @param node1 [Object] First node
      # @param node2 [Object] Second node
      # @param diff1 [String] Difference type for node1
      # @param diff2 [String] Difference type for node2
      # @param dimension [Symbol] The dimension of the difference
      # @return [String] Human-readable reason
      def self.build_reason(node1, node2, diff1, diff2, dimension)
        # For deleted/inserted nodes, include namespace information if available
        if dimension == :text_content && (node1.nil? || node2.nil?)
          node = node1 || node2
          if node.respond_to?(:name) && node.respond_to?(:namespace_uri)
            ns = node.namespace_uri
            ns_info = if ns.nil? || ns.empty?
                        ""
                      else
                        " (namespace: #{ns})"
                      end
            return "element '#{node.name}'#{ns_info}: #{diff1} vs #{diff2}"
          end
        end

        "#{diff1} vs #{diff2}"
      end

      # Enrich DiffNode with canonical path, serialized content, and attributes
      # This extracts presentation-ready metadata from nodes for Stage 4 rendering
      #
      # @param node1 [Object, nil] First node
      # @param node2 [Object, nil] Second node
      # @return [Hash] Enriched metadata hash
      def self.enrich_metadata(node1, node2)
        {
          path: build_path(node1 || node2),
          serialized_before: serialize(node1),
          serialized_after: serialize(node2),
          attributes_before: extract_attributes(node1),
          attributes_after: extract_attributes(node2),
        }
      end

      # Build canonical path for a node
      #
      # @param node [Object] Node to build path for
      # @return [String, nil] Canonical path with ordinal indices
      def self.build_path(node)
        return nil if node.nil?

        Canon::Diff::PathBuilder.build(node, format: :document)
      end

      # Serialize a node to string for display
      #
      # @param node [Object, nil] Node to serialize
      # @return [String, nil] Serialized content
      def self.serialize(node)
        return nil if node.nil?

        Canon::Diff::NodeSerializer.serialize(node)
      end

      # Extract attributes from a node as a normalized hash
      #
      # @param node [Object, nil] Node to extract attributes from
      # @return [Hash, nil] Normalized attributes hash
      def self.extract_attributes(node)
        return nil if node.nil?

        Canon::Diff::NodeSerializer.extract_attributes(node)
      end
    end
  end
end
