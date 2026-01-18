# frozen_string_literal: true

require_relative "markup_comparer"
require_relative "../xml_parser"

module Canon
  module Comparison
    # XML document comparison
    #
    # Provides XML-specific comparison behavior, including:
    # - XML namespace handling
    # - DOCTYPE processing
    # - XML-specific whitespace rules
    #
    # Inherits common comparison functionality from MarkupComparer.
    class XmlComparer < MarkupComparer
      class << self
        # Compare two XML documents
        #
        # @param doc1 [String, Object] First XML document
        # @param doc2 [String, Object] Second XML document
        # @param opts [Hash] Comparison options
        # @return [Boolean, ComparisonResult] Result of comparison
        def compare(doc1, doc2, opts = {})
          # Delegate to the existing XmlComparator
          require_relative "../xml_comparator"
          XmlComparator.equivalent?(doc1, doc2, opts)
        end

        # Parse an XML document from string or return as-is
        #
        # @param doc [String, Object] Document to parse
        # @param preprocessing [Symbol] Preprocessing option
        # @param match_opts [Hash] Resolved match options
        # @return [Object] Parsed document
        def parse_document(doc, preprocessing = :none, _match_opts = {})
          # Use the existing XmlParser for parsing
          XmlParser.parse_node(doc, preprocessing)
        end

        # Serialize an XML document to string
        #
        # @param doc [Object] Document to serialize
        # @return [String] Serialized document
        def serialize_document(doc)
          if doc.is_a?(Canon::Xml::Node)
            serialize_node_to_xml(doc)
          elsif doc.respond_to?(:to_xml)
            doc.to_xml
          else
            doc.to_s
          end
        end

        # Serialize a Canon::Xml::Node to XML string
        #
        # This utility method handles serialization of different node types
        # to their string representation for display and debugging purposes.
        #
        # @param node [Canon::Xml::Node, Object] Node to serialize
        # @return [String] XML string representation
        def serialize_node_to_xml(node)
          if node.is_a?(Canon::Xml::Nodes::RootNode)
            # Serialize all children of root
            node.children.map { |child| serialize_node_to_xml(child) }.join
          elsif node.is_a?(Canon::Xml::Nodes::ElementNode)
            # Serialize element with attributes and children
            attrs = node.attribute_nodes.map do |a|
              " #{a.name}=\"#{a.value}\""
            end.join
            children_xml = node.children.map do |c|
              serialize_node_to_xml(c)
            end.join

            if children_xml.empty?
              "<#{node.name}#{attrs}/>"
            else
              "<#{node.name}#{attrs}>#{children_xml}</#{node.name}>"
            end
          elsif node.is_a?(Canon::Xml::Nodes::TextNode)
            node.value
          elsif node.is_a?(Canon::Xml::Nodes::CommentNode)
            "<!--#{node.value}-->"
          elsif node.is_a?(Canon::Xml::Nodes::ProcessingInstructionNode)
            "<?#{node.target} #{node.data}?>"
          elsif node.respond_to?(:to_xml)
            node.to_xml
          else
            node.to_s
          end
        end
      end
    end
  end
end
