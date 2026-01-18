# frozen_string_literal: true

require_relative "markup_comparer"
require_relative "../html_parser"

module Canon
  module Comparison
    # HTML document comparison
    #
    # Provides HTML-specific comparison behavior, including:
    # - HTML4 vs HTML5 differences
    # - HTML-specific comment handling (comments in <style> and <script>)
    # - HTML whitespace normalization
    # - Rendering-aware comparison (browser-like behavior)
    #
    # Inherits common comparison functionality from MarkupComparer.
    class HtmlComparer < MarkupComparer
      class << self
        # Compare two HTML documents
        #
        # @param doc1 [String, Object] First HTML document
        # @param doc2 [String, Object] Second HTML document
        # @param opts [Hash] Comparison options
        # @return [Boolean, ComparisonResult] Result of comparison
        def compare(doc1, doc2, opts = {})
          # Delegate to the existing HtmlComparator
          require_relative "../html_comparator"
          HtmlComparator.equivalent?(doc1, doc2, opts)
        end

        # Parse an HTML document from string or return as-is
        #
        # @param doc [String, Object] Document to parse
        # @param preprocessing [Symbol] Preprocessing option
        # @param match_opts [Hash] Resolved match options
        # @return [Object] Parsed document
        def parse_document(doc, preprocessing = :none, _match_opts = {})
          # Use the existing HtmlParser for parsing
          HtmlParser.parse_node_for_semantic(doc, preprocessing)
        end

        # Serialize an HTML document to string
        #
        # @param doc [Object] Document to serialize
        # @return [String] Serialized document
        def serialize_document(doc)
          if doc.is_a?(Canon::Xml::Node)
            serialize_node_to_xml(doc)
          elsif doc.respond_to?(:to_html)
            doc.to_html
          elsif doc.respond_to?(:to_xml)
            doc.to_xml
          else
            doc.to_s
          end
        end

        # Serialize a Canon::Xml::Node to HTML string
        #
        # This utility method handles serialization of different node types
        # to their string representation for display and debugging purposes.
        #
        # @param node [Canon::Xml::Node, Object] Node to serialize
        # @return [String] HTML string representation
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

        private

        # Detect HTML version from a parsed node
        #
        # @param node [Object] Parsed node
        # @return [Symbol] :html4 or :html5
        def detect_html_version_from_node(_node)
          # Default to HTML5 for modern documents
          :html5
        end
      end
    end
  end
end
