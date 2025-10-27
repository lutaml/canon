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

        # Convert Nokogiri XML document/element to TreeNode
        #
        # @param node [Nokogiri::XML::Document, Nokogiri::XML::Element] XML node
        # @return [Core::TreeNode] Root tree node
        def to_tree(node)
          case node
          when Nokogiri::XML::Document
            # Start from root element
            to_tree(node.root)
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
          # Only return nil for truly empty text
          text.empty? ? nil : text
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
      end
    end
  end
end
