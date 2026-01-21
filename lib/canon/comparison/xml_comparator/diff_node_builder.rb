# frozen_string_literal: true

require "set"
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

        # For attribute presence differences, show what attributes differ
        if dimension == :attribute_presence
          attrs1 = extract_attributes(node1)
          attrs2 = extract_attributes(node2)
          return build_attribute_difference_reason(attrs1, attrs2)
        end

        # For text content differences, show the actual text (truncated if needed)
        if dimension == :text_content
          text1 = extract_text_content(node1)
          text2 = extract_text_content(node2)
          return build_text_difference_reason(text1, text2)
        end

        # Default reason
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

      # Build a clear reason message for attribute presence differences
      # Shows which attributes are only in node1, only in node2, or different values
      #
      # @param attrs1 [Hash, nil] First node's attributes
      # @param attrs2 [Hash, nil] Second node's attributes
      # @return [String] Clear explanation of the attribute difference
      def self.build_attribute_difference_reason(attrs1, attrs2)
        return "#{attrs1&.keys&.size || 0} vs #{attrs2&.keys&.size || 0} attributes" unless attrs1 && attrs2

        keys1 = attrs1.keys.to_set
        keys2 = attrs2.keys.to_set

        only_in_1 = keys1 - keys2
        only_in_2 = keys2 - keys1
        common = keys1 & keys2

        # Check if values differ for common keys
        different_values = common.select { |k| attrs1[k] != attrs2[k] }

        parts = []
        parts << "only in first: #{only_in_1.to_a.sort.join(', ')}" if only_in_1.any?
        parts << "only in second: #{only_in_2.to_a.sort.join(', ')}" if only_in_2.any?
        parts << "different values: #{different_values.sort.join(', ')}" if different_values.any?

        if parts.empty?
          "#{keys1.size} vs #{keys2.size} attributes (same names)"
        else
          parts.join('; ')
        end
      end

      # Extract text content from a node
      #
      # @param node [Object, nil] Node to extract text from
      # @return [String, nil] Text content or nil
      def self.extract_text_content(node)
        return nil if node.nil?

        # For Canon::Xml::Nodes::TextNode
        return node.value if node.respond_to?(:value) && node.is_a?(Canon::Xml::Nodes::TextNode)

        # For XML/HTML nodes with text_content method
        return node.text_content if node.respond_to?(:text_content)

        # For nodes with text method
        return node.text if node.respond_to?(:text)

        # For nodes with content method (Moxml::Text)
        return node.content if node.respond_to?(:content)

        # For nodes with value method (other types)
        return node.value if node.respond_to?(:value)

        # For simple text nodes or strings
        return node.to_s if node.is_a?(String)

        # For other node types, try to_s
        node.to_s
      rescue StandardError
        nil
      end

      # Build a clear reason message for text content differences
      # Shows the actual text content (truncated if too long)
      #
      # @param text1 [String, nil] First text content
      # @param text2 [String, nil] Second text content
      # @return [String] Clear explanation of the text difference
      def self.build_text_difference_reason(text1, text2)
        # Handle nil cases
        return "missing vs '#{truncate(text2)}'" if text1.nil? && text2
        return "'#{truncate(text1)}' vs missing" if text1 && text2.nil?
        return "both missing" if text1.nil? && text2.nil?

        # Both have content - show truncated versions
        "'#{truncate(text1)}' vs '#{truncate(text2)}'"
      end

      # Truncate text for display in reason messages
      #
      # @param text [String] Text to truncate
      # @param max_length [Integer] Maximum length
      # @return [String] Truncated text
      def self.truncate(text, max_length = 40)
        return "" if text.nil?

        text = text.to_s
        return text if text.length <= max_length

        "#{text[0...max_length]}..."
      end
    end
  end
end
