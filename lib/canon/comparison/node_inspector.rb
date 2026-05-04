# frozen_string_literal: true

module Canon
  module Comparison
    # Single source of truth for cross-backend node type operations.
    #
    # The comparison pipeline handles nodes from two backends:
    # * Canon::Xml::Node (+ RootNode, ElementNode, TextNode, etc.) —
    #   custom DOM built by SAX builder and DataModel.
    # * Nokogiri::XML::Node (+ subclasses) — native Nokogiri nodes used
    #   by the HTML comparator and some legacy paths.
    #
    # Every method here dispatches on type via +case/when+ (+is_a?+).
    # No +respond_to?+ — the types are known at every call site.
    module NodeInspector
      CANON_TEXT_TYPE = :text
      NOKOGIRI_TEXT_TYPE = defined?(Nokogiri::XML::Node::TEXT_NODE) ? Nokogiri::XML::Node::TEXT_NODE : 3

      # True when +node+ is a text node (whitespace, content, etc.).
      def self.text_node?(node)
        case node
        when Canon::Xml::Node
          node.node_type == CANON_TEXT_TYPE
        when Nokogiri::XML::Node
          node.node_type == NOKOGIRI_TEXT_TYPE
        else
          false
        end
      end

      # Extract the text content of +node+ as a String.
      def self.text_content(node)
        case node
        when Canon::Xml::Node
          node.value.to_s
        when Nokogiri::XML::Node
          node.content.to_s
        else
          node.to_s
        end
      end

      # True when +node+ is a text node whose content is whitespace-only.
      # Empty-string text nodes return false — those represent genuine
      # empty-vs-content asymmetry, not pretty-print indentation.
      def self.whitespace_only_text?(node)
        return false unless text_node?(node)

        text = text_content(node)
        !text.empty? && text.strip.empty?
      end

      # True when +node+ is a comment node.
      # For HTML, also detects comments that Nokogiri parses as TEXT nodes
      # (content like "<!-- comment -->" or escaped "<\\!-- comment -->").
      def self.comment_node?(node)
        case node
        when Canon::Xml::Node
          node.node_type == :comment
        when Nokogiri::XML::Node
          return true if node.comment?

          # HTML comments are parsed as TEXT nodes by Nokogiri
          if node.text?
            text_stripped = text_content(node).to_s.strip.gsub("\\", "")
            return true if text_stripped.start_with?("<!--") && text_stripped.end_with?("-->")
          end
          false
        else
          false
        end
      end

      # True when +node+ is an element node.
      def self.element_node?(node)
        case node
        when Canon::Xml::Node
          node.node_type == :element
        when Nokogiri::XML::Node
          node.element?
        else
          false
        end
      end

      # Extract parse-time errors carried on a node or its owning document.
      # Returns an Array of Strings.
      def self.parse_errors(node)
        case node
        when nil
          []
        when Canon::Xml::Node
          errors = node.parse_errors
          Array(errors).map(&:to_s)
        when Nokogiri::XML::Document, Nokogiri::HTML5::Document
          Array(node.errors).map(&:to_s)
        else
          []
        end
      end

      # Return the parent node of +node+, or nil when +node+ is not a
      # recognised DOM backend type or has no parent.
      def self.parent_of(node)
        case node
        when Canon::Xml::Node, Nokogiri::XML::Node
          node.parent
        end
      end
    end
  end
end
