# frozen_string_literal: true

require "nokogiri"

module Canon
  module TreeDiff
    module Adapters
      # HTMLAdapter converts Nokogiri HTML documents to TreeNode structures
      # and back, enabling semantic tree diffing on HTML documents.
      #
      # This adapter:
      # - Converts Nokogiri::HTML::Document to TreeNode tree
      # - Preserves element names, text content, and attributes
      # - Handles HTML-specific elements (script, style, etc.)
      # - Maintains document structure for round-trip conversion
      #
      # @example Convert HTML to TreeNode
      #   html = Nokogiri::HTML("<html><body><p>text</p></body></html>")
      #   adapter = HTMLAdapter.new
      #   tree = adapter.to_tree(html)
      #
      class HTMLAdapter
        # Convert Nokogiri HTML document/element to TreeNode
        #
        # @param node [Nokogiri::HTML::Document, Nokogiri::XML::Element] HTML node
        # @return [Core::TreeNode] Root tree node
        def to_tree(node)
          case node
          when Nokogiri::HTML::Document, Nokogiri::HTML4::Document
            # Start from html element or root element
            root = node.at_css("html") || node.root
            root ? to_tree(root) : nil
          when Nokogiri::XML::Element
            convert_element(node)
          else
            raise ArgumentError, "Unsupported node type: #{node.class}"
          end
        end

        # Convert TreeNode back to Nokogiri HTML
        #
        # @param tree_node [Core::TreeNode] Root tree node
        # @param doc [Nokogiri::HTML::Document] Optional document to use
        # @return [Nokogiri::HTML::Document, Nokogiri::XML::Element]
        def from_tree(tree_node, doc = nil)
          doc ||= Nokogiri::HTML::Document.new

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
        # @param element [Nokogiri::XML::Element] HTML element
        # @return [Core::TreeNode] Tree node
        def convert_element(element)
          # Get element name (lowercase for HTML)
          label = element.name.downcase

          # Collect attributes
          attributes = {}
          element.attributes.each do |name, attr|
            attributes[name] = attr.value
          end

          # Get text content (only direct text, not from children)
          text_value = extract_text_value(element)

          # Create tree node
          tree_node = Core::TreeNode.new(
            label: label,
            value: text_value,
            attributes: attributes,
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
        # @param element [Nokogiri::XML::Element] HTML element
        # @return [String, nil] Text content or nil
        def extract_text_value(element)
          # Get only direct text nodes, not from nested elements
          text_nodes = element.children.select(&:text?)
          text = text_nodes.map(&:text).join

          # Return nil for empty/whitespace-only text
          text.strip.empty? ? nil : text.strip
        end

        # Build Nokogiri element from TreeNode
        #
        # @param tree_node [Core::TreeNode] Tree node
        # @param doc [Nokogiri::HTML::Document] Document
        # @return [Nokogiri::XML::Element] HTML element
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
