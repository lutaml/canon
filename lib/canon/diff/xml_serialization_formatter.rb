# frozen_string_literal: true

module Canon
  module Diff
    # Detects and classifies XML serialization-level formatting differences.
    #
    # Serialization-level formatting differences are differences in XML syntax
    # that do not affect the semantic content of the document. These differences
    # arise from different valid ways to serialize the same semantic content.
    #
    # These differences are ALWAYS non-normative (formatting-only) regardless
    # of match options, because they are purely syntactic variations.
    #
    # Examples:
    # - Self-closing vs explicit closing tags: <tag/> vs <tag></tag>
    # - Attribute quote style: attr="value" vs attr='value' (parser-normalized)
    # - Whitespace within tags: <tag a="1" b="2"> vs <tag a="1"  b="2"> (parser-normalized)
    #
    # Note: Some serialization differences are normalized away by XML parsers
    # (attribute quotes, tag spacing). This class focuses on differences that
    # survive parsing and comparison, such as self-closing vs explicit closing.
    class XmlSerializationFormatter
      # Detect if a diff node represents an XML serialization formatting difference.
      #
      # Serialization formatting differences are ALWAYS non-normative because they
      # represent different valid serializations of the same semantic content.
      #
      # @param diff_node [DiffNode] The diff node to check
      # @return [Boolean] true if this is a serialization formatting difference
      def self.serialization_formatting?(diff_node)
        # Currently only handles text_content dimension
        # Future: add detection for other dimensions
        return false unless diff_node.dimension == :text_content

        empty_text_content_serialization_diff?(diff_node)
      end

      # Check if a text_content difference is from XML serialization format.
      #
      # Specifically detects self-closing tags (<tag/>) vs explicit closing tags
      # (<tag></tag>), which create different text node structures:
      # - Self-closing: no text node (nil)
      # - Explicit closing: empty or whitespace-only text node ("", " ", "\n", etc.)
      #
      # Per XML standards, these forms are semantically equivalent.
      #
      # @param diff_node [DiffNode] The diff node to check
      # @return [Boolean] true if this is a serialization formatting difference
      def self.empty_text_content_serialization_diff?(diff_node)
        return false unless diff_node.dimension == :text_content

        node1 = diff_node.node1
        node2 = diff_node.node2

        # Both nodes are nil - no actual difference, not a serialization formatting diff
        return false if node1.nil? && node2.nil?

        # Only one is nil (e.g., one doc has self-closing, other has text)
        # If the non-nil one is blank, it's still serialization formatting
        if node1.nil? || node2.nil?
          non_nil = node1 || node2
          return false unless text_node?(non_nil)

          text = extract_text_content(non_nil)
          return blank?(text)
        end

        # Both must be text nodes
        return false unless text_node?(node1) && text_node?(node2)

        text1 = extract_text_content(node1)
        text2 = extract_text_content(node2)

        # Check if both texts are blank/whitespace-only
        # This indicates self-closing vs explicit closing tag syntax
        blank?(text1) && blank?(text2)
      end

      # Check if a value is blank (nil or whitespace-only)
      # @param value [String, nil] Value to check
      # @return [Boolean] true if blank
      def self.blank?(value)
        value.nil? ||
          (value.respond_to?(:empty?) && value.empty?) ||
          (value.respond_to?(:strip) && value.strip.empty?)
      end

      # Check if a node is a text node
      # @param node [Object] The node to check
      # @return [Boolean] true if the node is a text node
      def self.text_node?(node)
        return false if node.nil?

        # Canon::Xml::Nodes::TextNode
        return true if node.is_a?(Canon::Xml::Nodes::TextNode)

        # Moxml::Text (check before generic node_type check)
        return true if node.is_a?(Moxml::Text)

        # Nokogiri text nodes (node_type returns integer constant like 3)
        return true if node.respond_to?(:node_type) &&
                       node.node_type.is_a?(Integer) &&
                       node.node_type == Nokogiri::XML::Node::TEXT_NODE

        # Moxml text nodes (node_type returns symbol) - for when using Moxml adapters
        return true if node.respond_to?(:node_type) && node.node_type == :text

        # String
        return true if node.is_a?(String)

        # Test doubles or objects with text node-like interface
        # Check if it has a value method (contains text content)
        return true if node.respond_to?(:value)

        false
      end

      # Extract text content from a node
      # @param node [Object] The node to extract text from
      # @return [String, nil] The text content or nil
      def self.extract_text_content(node)
        return nil if node.nil?

        # For TextNode with value attribute (Canon::Xml::Nodes::TextNode)
        return node.value if node.respond_to?(:value) && node.is_a?(Canon::Xml::Nodes::TextNode)

        # For XML/HTML nodes with text_content method
        return node.text_content if node.respond_to?(:text_content)

        # For nodes with content method (try before text, as Moxml::Text.text returns "")
        return node.content if node.respond_to?(:content)

        # For nodes with text method
        return node.text if node.respond_to?(:text)

        # For nodes with value method (other types)
        return node.value if node.respond_to?(:value)

        # For simple text nodes or strings
        return node.to_s if node.is_a?(String)

        # For other node types, try to_s
        node.to_s
      rescue StandardError
        # If extraction fails, return nil (not a serialization difference)
        nil
      end

      private_class_method :blank?, :text_node?, :extract_text_content, :empty_text_content_serialization_diff?
    end
  end
end
