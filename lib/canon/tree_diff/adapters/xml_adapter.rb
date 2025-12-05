# frozen_string_literal: true

require "nokogiri"

module Canon
  module TreeDiff
    module Adapters
      # XMLAdapter converts Nokogiri XML documents to TreeNode structures
      # and back, enabling semantic tree diffing on XML documents.
      #
      # This adapter:
      # - Converts Nokogiri::XML::Document to TreeNode tree
      # - Preserves element names, text content, and attributes
      # - Handles namespaces appropriately
      # - Maintains document structure for round-trip conversion
      #
      # @example Convert XML to TreeNode
      #   xml = Nokogiri::XML("<root><child>text</child></root>")
      #   adapter = XMLAdapter.new
      #   tree = adapter.to_tree(xml)
      #
      class XMLAdapter
        attr_reader :match_options

        # Initialize adapter with match options
        #
        # @param match_options [Hash] Match options for text/attribute normalization
        def initialize(match_options: {})
          @match_options = match_options
        end

        # Convert Nokogiri XML document/element or Canon::Xml::Node to TreeNode
        #
        # @param node [Nokogiri::XML::Document, Nokogiri::XML::Element, Canon::Xml::Node] XML node
        # @return [Core::TreeNode] Root tree node
        def to_tree(node)
          # Handle nil nodes
          return nil if node.nil?

          # Handle Canon::Xml::Node types first
          case node
          when Canon::Xml::Nodes::RootNode
            return to_tree_from_canon_root(node)
          when Canon::Xml::Nodes::ElementNode
            return to_tree_from_canon_element(node)
          when Canon::Xml::Nodes::TextNode
            return to_tree_from_canon_text(node)
          when Canon::Xml::Nodes::CommentNode
            return to_tree_from_canon_comment(node)
          end

          # Fallback to Nokogiri (legacy support)
          case node
          when Nokogiri::XML::Document
            # Start from root element
            root = node.root
            raise ArgumentError, "Document has no root element" if root.nil?

            to_tree(root)
          when Nokogiri::XML::Element
            convert_element(node)
          else
            raise ArgumentError, "Unsupported node type: #{node.class}"
          end
        end

        # Convert TreeNode back to Nokogiri XML
        #
        # @param tree_node [Core::TreeNode] Root tree node
        # @param doc [Nokogiri::XML::Document] Optional document to use
        # @return [Nokogiri::XML::Document, Nokogiri::XML::Element]
        def from_tree(tree_node, doc = nil)
          doc ||= Nokogiri::XML::Document.new

          element = build_element(tree_node, doc)

          if doc.root.nil?
            doc.root = element
            doc
          else
            element
          end
        end

        private

        # Convert a Nokogiri element to TreeNode
        #
        # @param element [Nokogiri::XML::Element] XML element
        # @return [Core::TreeNode] Tree node
        def convert_element(element)
          # Get element name (with namespace prefix if present)
          label = element.name

          # Create label that includes namespace URI to ensure elements
          # with different namespaces are treated as different nodes
          # Format: {namespace_uri}name or just name if no namespace
          namespace_uri = element.namespace&.href
          label = if namespace_uri && !namespace_uri.empty?
                    "{#{namespace_uri}}#{element.name}"
                  else
                    element.name
                  end

          # Collect attributes and sort them alphabetically
          # This ensures attribute order doesn't affect hash matching
          # (matches behavior of attribute_order: :ignore in match options)
          attributes = {}
          element.attributes.each do |name, attr|
            attributes[name] = attr.value
          end
          # Sort attributes by key to normalize order
          attributes = attributes.sort.to_h

          # Get text content (only direct text, not from children)
          text_value = extract_text_value(element)

          # Create tree node with source node reference
          tree_node = Core::TreeNode.new(
            label: label,
            value: text_value,
            attributes: attributes,
            source_node: element, # Preserve reference to original Nokogiri node
          )

          # Process child elements
          element.element_children.each do |child|
            child_node = convert_element(child)
            tree_node.add_child(child_node)
          end

          tree_node
        end

        # Extract direct text content from element
        #
        # Preserves original text for proper normalization during comparison.
        # Normalization happens in OperationDetector based on match_options,
        # NOT during tree conversion.
        #
        # For mixed content (text nodes + child elements), joins text nodes
        # with a space to prevent text from running together when elements
        # like <br/> separate the text.
        #
        # @param element [Nokogiri::XML::Element] XML element
        # @return [String, nil] Text content or nil
        def extract_text_value(element)
          # Get only direct text nodes, not from nested elements
          text_nodes = element.children.select(&:text?)

          # For mixed content (has both text nodes and element children),
          # join text nodes with space to handle implicit whitespace around
          # block-level elements like <br/>
          # Example: "Text<br/>More" should become "Text More" not "TextMore"
          separator = element.element_children.any? ? " " : ""
          text = text_nodes.map(&:text).join(separator)

          # CRITICAL FIX: Return original text without stripping
          # Normalization will be applied during comparison based on match_options
          # Only return nil for truly empty text or whitespace-only text
          text.strip.empty? ? nil : text
        end

        # Build Nokogiri element from TreeNode
        #
        # @param tree_node [Core::TreeNode] Tree node
        # @param doc [Nokogiri::XML::Document] Document
        # @return [Nokogiri::XML::Element] XML element
        def build_element(tree_node, doc)
          element = Nokogiri::XML::Element.new(tree_node.label, doc)

          # Add attributes
          tree_node.attributes.each do |name, value|
            element[name] = value
          end

          # Add text content if present
          if tree_node.value && !tree_node.value.empty?
            element.content = tree_node.value
          end

          # Add child elements
          tree_node.children.each do |child|
            child_element = build_element(child, doc)
            element.add_child(child_element)
          end

          element
        end

        # Convert Canon::Xml::Nodes::RootNode to TreeNode
        #
        # @param root_node [Canon::Xml::Nodes::RootNode] Root node
        # @return [Core::TreeNode, nil] Tree node for first child (document element)
        def to_tree_from_canon_root(root_node)
          # Root node: process first child (document element)
          return nil if root_node.children.empty?

          to_tree(root_node.children.first)
        end

        # Convert Canon::Xml::Nodes::ElementNode to TreeNode
        #
        # @param element_node [Canon::Xml::Nodes::ElementNode] Element node
        # @return [Core::TreeNode] Tree node
        def to_tree_from_canon_element(element_node)
          # Create label that includes namespace URI to ensure elements
          # with different namespaces are treated as different nodes
          # Format: {namespace_uri}name or just name if no namespace
          namespace_uri = element_node.namespace_uri
          label = if namespace_uri && !namespace_uri.empty?
                    "{#{namespace_uri}}#{element_node.name}"
                  else
                    element_node.name
                  end

          # Create TreeNode from Canon::Xml::Nodes::ElementNode
          tree_node = Core::TreeNode.new(
            label: label,
            value: nil, # Elements don't have values
            attributes: extract_canon_attributes(element_node),
            children: [],
            source_node: element_node, # Preserve reference to Canon node
          )

          # Process children recursively
          element_node.children.each do |child|
            child_tree = to_tree(child)
            tree_node.add_child(child_tree) if child_tree
          end

          tree_node
        end

        # Convert Canon::Xml::Nodes::TextNode to TreeNode
        #
        # @param text_node [Canon::Xml::Nodes::TextNode] Text node
        # @return [Core::TreeNode, nil] Tree node or nil for whitespace-only text
        def to_tree_from_canon_text(text_node)
          # Extract text value
          text_value = text_node.value.to_s

          # Return nil for whitespace-only text
          return nil if text_value.strip.empty?

          Core::TreeNode.new(
            label: "text",
            value: text_value,
            attributes: {},
            children: [],
            source_node: text_node,
          )
        end

        # Convert Canon::Xml::Nodes::CommentNode to TreeNode
        #
        # @param comment_node [Canon::Xml::Nodes::CommentNode] Comment node
        # @return [Core::TreeNode] Tree node
        def to_tree_from_canon_comment(comment_node)
          Core::TreeNode.new(
            label: "comment",
            value: comment_node.value,
            attributes: {},
            children: [],
            source_node: comment_node,
          )
        end

        # Extract attributes from Canon::Xml::Nodes::ElementNode
        #
        # @param element_node [Canon::Xml::Nodes::ElementNode] Element node
        # @return [Hash] Attributes hash sorted by key
        def extract_canon_attributes(element_node)
          # Canon::Xml::Nodes::ElementNode has attribute_nodes array
          attrs = {}
          element_node.attribute_nodes.each do |attr|
            attrs[attr.name] = attr.value
          end
          # Sort attributes by key to normalize order
          attrs.sort.to_h
        end
      end
    end
  end
end
