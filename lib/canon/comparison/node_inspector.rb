# frozen_string_literal: true

module Canon
  module Comparison
    # Single source of truth for cross-backend node type operations.
    #
    # The comparison pipeline handles nodes from multiple sources:
    # * Canon::Xml::Node (+ RootNode, ElementNode, TextNode, etc.) —
    #   custom DOM built by SAX builder and DataModel.
    # * Canon::TreeDiff::Core::TreeNode — semantic tree diff nodes.
    # * Backend-specific nodes (Nokogiri or Moxml) — live parsed nodes.
    #
    # All type dispatch uses backend-branching (`if XmlBackend.nokogiri?`)
    # rather than `case/when` with constant references. This prevents
    # NameError when Nokogiri constants are undefined under Opal.
    #
    # Every node query in the codebase should go through this module.
    # Do not create private dispatch methods in consumers.
    module NodeInspector
      NOKOGIRI_TEXT_TYPE = defined?(Nokogiri::XML::Node::TEXT_NODE) ? Nokogiri::XML::Node::TEXT_NODE : 3

      # --- Type predicates ---

      def self.text_node?(node)
        return false unless node
        return node.node_type == :text if node.is_a?(Canon::Xml::Node)

        if XmlBackend.nokogiri?
          node.is_a?(Nokogiri::XML::Text) || node.is_a?(Moxml::Text)
        else
          node.is_a?(Moxml::Text)
        end
      end

      def self.element_node?(node)
        return false unless node
        return node.node_type == :element if node.is_a?(Canon::Xml::Node)

        if XmlBackend.nokogiri?
          node.is_a?(Nokogiri::XML::Element) || node.is_a?(Moxml::Element)
        else
          node.is_a?(Moxml::Element)
        end
      end

      def self.comment_node?(node)
        return false unless node
        return node.node_type == :comment if node.is_a?(Canon::Xml::Node)

        if XmlBackend.nokogiri?
          return true if node.is_a?(Nokogiri::XML::Node) && node.comment?

          # HTML comments are parsed as TEXT nodes by Nokogiri
          if node.is_a?(Nokogiri::XML::Node) && node.text?
            text_stripped = text_content(node).to_s.strip.gsub("\\", "")
            return true if text_stripped.start_with?("<!--") && text_stripped.end_with?("-->")
          end
          false
        else
          node.is_a?(Moxml::Comment)
        end
      end

      def self.document?(node)
        return node.node_type == :root if node.is_a?(Canon::Xml::Node)

        XmlParsing.document?(node)
      end

      def self.document_fragment?(node)
        return false unless node
        return false unless node.is_a?(Canon::Xml::Nodes::RootNode)

        node.fragment?
      end

      # True when +node+ is a text node whose content is whitespace-only.
      # Empty-string text nodes return false — those represent genuine
      # empty-vs-content asymmetry, not pretty-print indentation.
      def self.whitespace_only_text?(node)
        return false unless text_node?(node)

        text = text_content(node)
        !text.empty? && text.strip.empty?
      end

      # --- Noise classification ---

      def self.noise_dimension_for(node)
        if whitespace_only_text?(node)
          :whitespace_adjacency
        elsif comment_node?(node)
          :comments
        end
      end

      def self.noise_node?(node)
        !noise_dimension_for(node).nil?
      end

      # --- Node queries ---

      # Unified node name extraction across all node types.
      def self.name(node)
        return nil unless node
        return node.name if node.is_a?(Canon::Xml::Node)
        return node.label if node.is_a?(Canon::TreeDiff::Core::TreeNode)

        XmlParsing.name(node)
      end

      # Unified parent access across all node types.
      def self.parent(node)
        return nil unless node
        return node.parent if node.is_a?(Canon::Xml::Node)
        return node.parent if node.is_a?(Canon::TreeDiff::Core::TreeNode)

        XmlParsing.parent(node)
      end

      # Unified children access across all node types.
      def self.children(node)
        return [] unless node
        return node.children if node.is_a?(Canon::Xml::Node)
        return node.children || [] if node.is_a?(Canon::TreeDiff::Core::TreeNode)

        XmlParsing.children(node)
      end

      # Extract the text content of +node+ as a String.
      def self.text_content(node)
        case node
        when Canon::Xml::Nodes::TextNode
          node.value.to_s
        when Canon::Xml::Node
          node.text_content.to_s
        when Moxml::Text
          node.content.to_s
        else
          XmlParsing.text_content(node).to_s
        end
      end

      # Unified node type that always returns a symbol.
      # Returns nil for unrecognised nodes.
      def self.node_type(node)
        return nil unless node
        return node.node_type if node.is_a?(Canon::Xml::Node)

        if node.is_a?(Canon::TreeDiff::Core::TreeNode)
          node.type&.to_sym
        else
          XmlParsing.node_type(node)
        end
      end

      # Unified attribute value access.
      def self.attribute_value(node, attr_name)
        return nil unless node

        if node.is_a?(Canon::Xml::Nodes::ElementNode)
          attr = node.attribute_nodes.find { |a| a.name == attr_name.to_s }
          attr&.value
        elsif node.is_a?(Canon::Xml::Node)
          nil
        else
          XmlParsing.attribute_value(node, attr_name)
        end
      end

      # Unified namespace URI access.
      def self.namespace_uri(node)
        return nil unless node

        if node.is_a?(Canon::Xml::Node)
          node.is_a?(Canon::Xml::Nodes::ElementNode) ? node.namespace_uri : nil
        else
          XmlParsing.namespace_uri(node)
        end
      end

      # Extract parse-time errors carried on a node or its owning document.
      def self.parse_errors(node)
        return [] if node.nil?
        return Array(node.parse_errors).map(&:to_s) if node.is_a?(Canon::Xml::Node)

        if XmlBackend.nokogiri?
          if node.is_a?(Nokogiri::XML::Document) || node.is_a?(Nokogiri::HTML5::Document)
            Array(node.errors).map(&:to_s)
          else
            []
          end
        else
          []
        end
      end

      # Deprecated: use NodeInspector.parent instead.
      def self.parent_of(node)
        parent(node)
      end
    end
  end
end
