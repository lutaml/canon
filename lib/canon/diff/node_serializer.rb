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
          # Use original text (with entity references) if available,
          # otherwise fall back to value (decoded text)
          return node.original || node.value
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

        # Handle Nokogiri/moxml nodes
        if Canon::XmlParsing.xml_node?(node)
          return Canon::XmlParsing.serialize(node)
        end

        # Handle tree diff nodes and other objects with serialization
        if node.is_a?(Canon::TreeDiff::Core::TreeNode)
          return serialize_treenode(node)
        end

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

        # Handle Nokogiri/moxml elements via XmlParsing
        if Canon::XmlParsing.element?(node)
          attrs = {}
          Canon::XmlParsing.attributes(node).each do |attr|
            attrs[attr.name] = attr.value
          end
          return attrs
        end

        # Handle other elements with attributes method
        if node.is_a?(Canon::Xml::Node)
          return {}
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

        # Handle Nokogiri/moxml elements
        name = Canon::XmlParsing.name(node)
        return name.to_s if name

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

        # Handle Canon::Xml::Node
        if node.is_a?(Canon::Xml::Node)
          return node.text_content.to_s
        end

        # Handle Nokogiri/moxml nodes
        Canon::XmlParsing.text_content(node).to_s
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
