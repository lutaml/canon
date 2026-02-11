# frozen_string_literal: true

require_relative "../comparison" # Load base module with constants
require_relative "../diff/diff_node"
require_relative "../diff/path_builder"

module Canon
  module Comparison
    # Base class for markup document comparison (XML, HTML)
    #
    # Provides shared comparison functionality for markup documents,
    # including node type checking, text extraction, filtering,
    # and difference creation.
    #
    # Format-specific comparators (XmlComparator, HtmlComparator)
    # inherit from this class and add format-specific behavior.
    class MarkupComparator
      class << self
        # Add a difference to the differences array
        #
        # Creates a DiffNode with enriched metadata including path,
        # serialized content, and attributes for Stage 4 rendering.
        #
        # @param node1 [Object, nil] First node
        # @param node2 [Object, nil] Second node
        # @param diff1 [Symbol] Difference type for node1
        # @param diff2 [Symbol] Difference type for node2
        # @param dimension [Symbol] The match dimension causing this difference
        # @param _opts [Hash] Options (unused but kept for interface compatibility)
        # @param differences [Array] Array to append difference to
        def add_difference(node1, node2, diff1, diff2, dimension, _opts,
                           differences)
          # All differences must be DiffNode objects (OO architecture)
          if dimension.nil?
            raise ArgumentError,
                  "dimension required for DiffNode"
          end

          # Build informative reason message
          reason = build_difference_reason(node1, node2, diff1, diff2,
                                           dimension)

          # Enrich with path, serialized content, and attributes for Stage 4 rendering
          metadata = enrich_diff_metadata(node1, node2)

          diff_node = Canon::Diff::DiffNode.new(
            node1: node1,
            node2: node2,
            dimension: dimension,
            reason: reason,
            **metadata,
          )
          differences << diff_node
        end

        # Enrich DiffNode with canonical path, serialized content, and attributes
        # This extracts presentation-ready metadata from nodes for Stage 4 rendering
        #
        # @param node1 [Object, nil] First node
        # @param node2 [Object, nil] Second node
        # @return [Hash] Enriched metadata hash
        def enrich_diff_metadata(node1, node2)
          {
            path: build_path_for_node(node1 || node2),
            serialized_before: serialize_node(node1),
            serialized_after: serialize_node(node2),
            attributes_before: extract_attributes(node1),
            attributes_after: extract_attributes(node2),
          }
        end

        # Build canonical path for a node
        #
        # @param node [Object] Node to build path for
        # @return [String, nil] Canonical path with ordinal indices
        def build_path_for_node(node)
          return nil if node.nil?

          Canon::Diff::PathBuilder.build(node, format: :document)
        end

        # Serialize a node to string for display
        #
        # @param node [Object, nil] Node to serialize
        # @return [String, nil] Serialized content
        def serialize_node(node)
          return nil if node.nil?

          # Canon::Xml::Node types
          if node.is_a?(Canon::Xml::Nodes::RootNode)
            # Serialize all children of root
            node.children.map { |child| serialize_node(child) }.join
          elsif node.is_a?(Canon::Xml::Nodes::ElementNode)
            serialize_element_node(node)
          elsif node.is_a?(Canon::Xml::Nodes::TextNode)
            node.value
          elsif node.is_a?(Canon::Xml::Nodes::CommentNode)
            "<!--#{node.value}-->"
          elsif node.is_a?(Canon::Xml::Nodes::ProcessingInstructionNode)
            "<?#{node.target} #{node.data}?>"
          elsif node.respond_to?(:to_xml)
            node.to_xml
          elsif node.respond_to?(:to_html)
            node.to_html
          else
            node.to_s
          end
        end

        # Extract attributes from a node
        #
        # @param node [Object, nil] Node to extract attributes from
        # @return [Hash, nil] Hash of attribute name => value pairs
        def extract_attributes(node)
          return nil if node.nil?

          # Canon::Xml::Node ElementNode
          if node.is_a?(Canon::Xml::Nodes::ElementNode)
            node.attribute_nodes.each_with_object({}) do |attr, hash|
              hash[attr.name] = attr.value
            end
          # Nokogiri nodes
          elsif node.respond_to?(:attributes)
            node.attributes.each_with_object({}) do |(_, attr), hash|
              hash[attr.name] = attr.value
            end
          else
            {}
          end
        end

        # Filter children based on options
        #
        # Removes nodes that should be excluded from comparison based on
        # options like :ignore_nodes, :ignore_comments, etc.
        #
        # @param children [Array] Array of child nodes
        # @param opts [Hash] Comparison options
        # @return [Array] Filtered array of children
        def filter_children(children, opts)
          children.reject do |child|
            node_excluded?(child, opts)
          end
        end

        # Check if node should be excluded from comparison
        #
        # @param node [Object] Node to check
        # @param opts [Hash] Comparison options
        # @return [Boolean] true if node should be excluded
        def node_excluded?(node, opts)
          return false if node.nil?

          return true if opts[:ignore_nodes]&.include?(node)
          return true if opts[:ignore_comments] && comment_node?(node)
          return true if opts[:ignore_text_nodes] && text_node?(node)

          # Check match options
          match_opts = opts[:match_opts]
          return false unless match_opts

          # Filter comments based on match options and format
          # HTML: Filter comments to avoid spurious differences from zip pairing
          #       BUT only when not in verbose mode (verbose needs differences recorded)
          # XML: Don't filter comments (allow informative differences to be recorded)
          if match_opts[:comments] == :ignore && comment_node?(node)
            # In verbose mode, don't filter comments - we want to record the differences
            return false if opts[:verbose]

            # Only filter comments for HTML, not XML (when not verbose)
            format = opts[:format] || match_opts[:format]
            if %i[html html4 html5].include?(format)
              return true
            end
          end

          # Filter out whitespace-only text nodes based on structural_whitespace setting
          if match_opts && %i[ignore
                              normalize].include?(match_opts[:structural_whitespace]) && text_node?(node)
            text = node_text(node)
            return true if MatchOptions.normalize_text(text).empty?
          end

          false
        end

        # Check if two nodes are the same type
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @return [Boolean] true if nodes are same type
        def same_node_type?(node1, node2)
          return false if node1.class != node2.class

          # For Nokogiri/Canon::Xml nodes, check node type
          if node1.respond_to?(:node_type) && node2.respond_to?(:node_type)
            node1.node_type == node2.node_type
          else
            true
          end
        end

        # Check if a node is a comment node
        #
        # For XML/XHTML, this checks the node's comment? method or node_type.
        # For HTML, this also checks TEXT nodes that contain HTML-style comments
        # (Nokogiri parses HTML comments as TEXT nodes with content like "<!-- comment -->"
        # or escaped like "<\\!-- comment -->" in full HTML documents).
        #
        # @param node [Object] Node to check
        # @return [Boolean] true if node is a comment
        def comment_node?(node)
          return true if node.respond_to?(:comment?) && node.comment?
          return true if node.respond_to?(:node_type) && node.node_type == :comment

          # HTML comments are parsed as TEXT nodes by Nokogiri
          # Check if this is a text node with HTML comment content
          if text_node?(node)
            text = node_text(node)
            # Strip whitespace and backslashes for comparison
            # Nokogiri escapes HTML comments as "<\\!-- comment -->" in full documents
            text_stripped = text.to_s.strip.gsub("\\", "")
            return true if text_stripped.start_with?("<!--") && text_stripped.end_with?("-->")
          end

          false
        end

        # Check if a node is a text node
        #
        # @param node [Object] Node to check
        # @return [Boolean] true if node is a text node
        def text_node?(node)
          node.respond_to?(:text?) && node.text? &&
            !node.respond_to?(:element?) ||
            node.respond_to?(:node_type) && node.node_type == :text
        end

        # Get text content from a node
        #
        # @param node [Object] Node to get text from
        # @return [String] Text content
        def node_text(node)
          # Canon::Xml::Node TextNode uses .value
          if node.respond_to?(:value)
            node.value.to_s
          # Nokogiri nodes use .content
          elsif node.respond_to?(:content)
            node.content.to_s
          else
            node.to_s
          end
        end

        # Check if difference between two texts is only whitespace
        #
        # @param text1 [String] First text
        # @param text2 [String] Second text
        # @return [Boolean] true if difference is only in whitespace
        def whitespace_only_difference?(text1, text2)
          # Normalize both texts (collapse/trim whitespace)
          norm1 = MatchOptions.normalize_text(text1)
          norm2 = MatchOptions.normalize_text(text2)

          # If normalized texts are the same, the difference was only whitespace
          norm1 == norm2
        end

        # Build a human-readable reason for a difference
        #
        # @param node1 [Object, nil] First node
        # @param node2 [Object, nil] Second node
        # @param diff1 [Symbol] Difference type for node1
        # @param diff2 [Symbol] Difference type for node2
        # @param dimension [Symbol] The dimension of the difference
        # @return [String] Human-readable reason
        def build_difference_reason(node1, node2, diff1, diff2, dimension)
          # For attribute presence differences, show what attributes differ
          if dimension == :attribute_presence
            attrs1 = extract_attributes(node1)
            attrs2 = extract_attributes(node2)
            return build_attribute_difference_reason(attrs1, attrs2)
          end

          # For text content differences, show the actual text (truncated if needed)
          if dimension == :text_content
            text1 = extract_text_content_from_node(node1)
            text2 = extract_text_content_from_node(node2)
            return build_text_difference_reason(text1, text2)
          end

          # Default reason - can be overridden in subclasses
          "#{diff1} vs #{diff2}"
        end

        # Build a clear reason message for attribute presence differences
        # Shows which attributes are only in node1, only in node2, or different values
        #
        # @param attrs1 [Hash, nil] First node's attributes
        # @param attrs2 [Hash, nil] Second node's attributes
        # @return [String] Clear explanation of the attribute difference
        def build_attribute_difference_reason(attrs1, attrs2)
          return "#{attrs1&.keys&.size || 0} vs #{attrs2&.keys&.size || 0} attributes" unless attrs1 && attrs2

          require "set"
          keys1 = attrs1.keys.to_set
          keys2 = attrs2.keys.to_set

          only_in_1 = keys1 - keys2
          only_in_2 = keys2 - keys1
          common = keys1 & keys2

          # Check if values differ for common keys
          different_values = common.reject { |k| attrs1[k] == attrs2[k] }

          parts = []
          parts << "only in first: #{only_in_1.to_a.sort.join(', ')}" if only_in_1.any?
          parts << "only in second: #{only_in_2.to_a.sort.join(', ')}" if only_in_2.any?
          parts << "different values: #{different_values.sort.join(', ')}" if different_values.any?

          if parts.empty?
            "#{keys1.size} vs #{keys2.size} attributes (same names)"
          else
            parts.join("; ")
          end
        end

        # Extract text content from a node for diff reason
        #
        # @param node [Object, nil] Node to extract text from
        # @return [String, nil] Text content or nil
        def extract_text_content_from_node(node)
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
        def build_text_difference_reason(text1, text2)
          # Handle nil cases
          return "missing vs '#{truncate_text(text2)}'" if text1.nil? && text2
          return "'#{truncate_text(text1)}' vs missing" if text1 && text2.nil?
          return "both missing" if text1.nil? && text2.nil?

          # Both have content - show truncated versions
          "'#{truncate_text(text1)}' vs '#{truncate_text(text2)}'"
        end

        # Truncate text for display in reason messages
        #
        # @param text [String] Text to truncate
        # @param max_length [Integer] Maximum length
        # @return [String] Truncated text
        def truncate_text(text, max_length = 40)
          return "" if text.nil?

          text = text.to_s
          return text if text.length <= max_length

          "#{text[0...max_length]}..."
        end

        # Serialize an element node to string
        #
        # @param node [Canon::Xml::Nodes::ElementNode] Element node
        # @return [String] Serialized element
        def serialize_element_node(node)
          attrs = node.attribute_nodes.map do |a|
            " #{a.name}=\"#{a.value}\""
          end.join
          children_xml = node.children.map { |c| serialize_node(c) }.join

          if children_xml.empty?
            "<#{node.name}#{attrs}/>"
          else
            "<#{node.name}#{attrs}>#{children_xml}</#{node.name}>"
          end
        end

        # Determine the appropriate dimension for a node type
        #
        # @param node [Object] The node to check
        # @return [Symbol] The dimension symbol
        def determine_node_dimension(node)
          # Canon::Xml::Node types
          if node.respond_to?(:node_type) && node.node_type.is_a?(Symbol)
            case node.node_type
            when :comment then :comments
            when :text, :cdata then :text_content
            when :processing_instruction then :processing_instructions
            else :text_content
            end
          # Moxml/Nokogiri types
          elsif node.respond_to?(:comment?) && node.comment?
            :comments
          elsif node.respond_to?(:text?) && node.text?
            :text_content
          elsif node.respond_to?(:cdata?) && node.cdata?
            :text_content
          elsif node.respond_to?(:processing_instruction?) && node.processing_instruction?
            :processing_instructions
          else
            :text_content
          end
        end
      end
    end
  end
end
