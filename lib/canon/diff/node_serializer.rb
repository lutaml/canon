# frozen_string_literal: true

require_relative "../xml/data_model"
require_relative "../xml/nodes/text_node"
require_relative "../xml/nodes/comment_node"
require_relative "../xml/nodes/element_node"
require_relative "../xml/nodes/processing_instruction_node"
require_relative "../xml/nodes/root_node"

module Canon
  module Diff
    # Serializes nodes from different parsing libraries into canonical strings
    # This abstraction allows Canon to work with any parsing library
    # (Nokogiri, Moxml, etc.) without being tied to a specific implementation.
    #
    # This is library-agnostic because it detects node type and uses
    # the appropriate serialization method.
    class NodeSerializer
      # Serialize a node to a string for display
      # Handles both Nokogiri and Canon nodes
      #
      # @param node [Object] Node to serialize (Nokogiri, Canon, or nil)
      # @return [String] Serialized string representation
      def self.serialize(node)
        return "" if node.nil?

        # Handle Canon::Xml::Nodes::TextNode
        if node.is_a?(Canon::Xml::Nodes::TextNode)
          return node.value.to_s
        end

        # Handle Canon::Xml::Nodes::CommentNode
        if node.is_a?(Canon::Xml::Nodes::CommentNode)
          return "<!--#{node.value}-->"
        end

        # Handle Canon::Xml::Nodes::ElementNode
        if node.is_a?(Canon::Xml::Nodes::ElementNode)
          return serialize_element_node(node)
        end

        # Handle Canon::Xml::Nodes::ProcessingInstructionNode
        if node.is_a?(Canon::Xml::Nodes::ProcessingInstructionNode)
          return "<?#{node.target} #{node.data}?>"
        end

        # Handle Canon::Xml::Nodes::RootNode - serialize children
        if node.is_a?(Canon::Xml::Nodes::RootNode)
          return node.children.map { |child| serialize(child) }.join
        end

        # Handle Nokogiri nodes
        if node.respond_to?(:to_html)
          return node.to_html
        end

        if node.respond_to?(:to_xml)
          return node.to_xml
        end

        # Fallback to string
        node.to_s
      end

      # Serialize an ElementNode to HTML/XML string
      #
      # @param element [Canon::Xml::Nodes::ElementNode] Element to serialize
      # @return [String] Serialized element
      def self.serialize_element_node(element)
        # Build opening tag with attributes
        tag = "<#{element.name}"

        # Add attributes
        element.sorted_attribute_nodes.each do |attr|
          tag += " #{attr.name}=\"#{attr.value}\""
        end

        # Check if element has children
        if element.children.empty?
          # Self-closing tag for empty elements
          "#{tag}/>"
        else
          # Full element with children
          content = element.children.map { |child| serialize(child) }.join
          "#{tag}>#{content}</#{element.name}>"
        end
      end

      # Extract attributes from a node as a normalized hash
      # Handles both Nokogiri and Canon nodes
      #
      # @param node [Object] Node to extract attributes from
      # @return [Hash] Normalized attributes hash
      def self.extract_attributes(node)
        return {} if node.nil?

        # Handle Canon::Xml::Nodes::ElementNode
        if node.is_a?(Canon::Xml::Nodes::ElementNode)
          attrs = {}
          node.attribute_nodes.each do |attr|
            attrs[attr.name] = attr.value
          end
          return attrs
        end

        # Handle Nokogiri elements
        if node.respond_to?(:attributes) && node.attributes.is_a?(Hash)
          attrs = {}
          node.attributes.each do |name, attr|
            # Nokogiri attributes have different structure
            value = if attr.respond_to?(:value)
                      attr.value
                    elsif attr.is_a?(String)
                      attr
                    else
                      attr.to_s
                    end
            attrs[name] = value
          end
          return attrs
        end

        # Handle TreeNode attributes (already a hash)
        if node.is_a?(Hash)
          return node
        end

        {}
      end

      # Get element name from a node
      # Handles both Nokogiri and Canon nodes
      #
      # @param node [Object] Node to get name from
      # @return [String] Element name
      def self.element_name(node)
        return "" if node.nil?

        # Handle Canon::Xml::Nodes::ElementNode
        if node.is_a?(Canon::Xml::Nodes::ElementNode)
          return node.name
        end

        # Handle Nokogiri elements
        if node.respond_to?(:name)
          return node.name.to_s
        end

        ""
      end

      # Get text content from a node
      # Handles both Nokogiri and Canon nodes
      #
      # @param node [Object] Node to get text from
      # @return [String] Text content
      def self.text_content(node)
        return "" if node.nil?

        # Handle Canon::Xml::Nodes::TextNode
        if node.is_a?(Canon::Xml::Nodes::TextNode)
          return node.value.to_s
        end

        # Handle Nokogiri text nodes
        if node.respond_to?(:text)
          return node.text.to_s
        end

        if node.respond_to?(:content)
          return node.content.to_s
        end

        ""
      end

      # Serialize attributes to string format
      # Returns attributes in " name=\"value\"" format
      #
      # @param attributes [Hash] Attributes hash
      # @return [String] Serialized attributes
      def self.serialize_attributes(attributes)
        return "" if attributes.nil? || attributes.empty?

        attributes.sort.map do |name, value|
          " #{name}=\"#{value}\""
        end.join
      end
    end
  end
end
