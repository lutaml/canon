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

          # Check structural_whitespace match option
          match_opts = opts[:match_opts]
          # Filter out whitespace-only text nodes
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
        # @param node [Object] Node to check
        # @return [Boolean] true if node is a comment
        def comment_node?(node)
          node.respond_to?(:comment?) && node.comment? ||
            node.respond_to?(:node_type) && node.node_type == :comment
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
        def build_difference_reason(_node1, _node2, diff1, diff2, dimension)
          # Default reason - can be overridden in subclasses
          "Difference in #{dimension}: #{diff1} vs #{diff2}"
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
