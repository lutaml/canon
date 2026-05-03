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

        case node
        when Canon::Xml::Nodes::TextNode
          true
        when Canon::Xml::Node
          node.node_type == :text
        when Nokogiri::XML::Node
          node.node_type == Nokogiri::XML::Node::TEXT_NODE
        when Moxml::Node
          node.text?
        when String
          true
        else
          false
        end
      end

      # Extract text content from a node
      # @param node [Object] The node to extract text from
      # @return [String, nil] The text content or nil
      def self.extract_text_content(node)
        return nil if node.nil?

        case node
        when Canon::Xml::Nodes::TextNode
          node.value
        when Canon::Xml::Node
          node.text_content
        when Nokogiri::XML::Node
          node.content.to_s
        when Moxml::Node
          node.content.to_s
        when String
          node
        else
          node.to_s
        end
      rescue StandardError
        nil
      end

      private_class_method :blank?, :text_node?, :extract_text_content,
                           :empty_text_content_serialization_diff?
    end
  end
end
