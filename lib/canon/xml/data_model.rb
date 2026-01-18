# frozen_string_literal: true

require "nokogiri"
require "set"
require_relative "../data_model"
require_relative "nodes/root_node"
require_relative "nodes/element_node"
require_relative "nodes/namespace_node"
require_relative "nodes/attribute_node"
require_relative "nodes/text_node"
require_relative "nodes/comment_node"
require_relative "nodes/processing_instruction_node"

module Canon
  module Xml
    # Builds XPath data model from XML
    class DataModel < Canon::DataModel
      # Build XPath data model from XML string
      #
      # @param xml_string [String] XML content to parse
      # @param preserve_whitespace [Boolean] Whether to preserve whitespace-only text nodes
      # @return [Nodes::RootNode] Root of the data model tree
      def self.from_xml(xml_string, preserve_whitespace: false)
        # Parse with Nokogiri
        doc = Nokogiri::XML(xml_string) do |config|
          config.nonet     # Disable network access
          config.strict    # Strict parsing
        end

        # Check for relative namespace URIs (prohibited by C14N 1.1)
        check_for_relative_namespace_uris(doc)

        # Convert to XPath data model
        build_from_nokogiri(doc, preserve_whitespace: preserve_whitespace)
      end

      # Alias for compatibility with base class interface
      def self.parse(xml_string)
        from_xml(xml_string)
      end

      # Serialize XML node to string
      #
      # @param node [Nodes::RootNode, Nodes::ElementNode] Node to serialize
      # @return [String] Serialized XML string
      def self.serialize(node)
        # Implementation will delegate to existing XML serialization
        # This is a placeholder for the base class interface
        node.to_s
      end

      # Check for relative namespace URIs (prohibited by C14N 1.1)
      # rubocop:disable Metrics/MethodLength
      def self.check_for_relative_namespace_uris(doc)
        doc.traverse do |node|
          next unless node.is_a?(Nokogiri::XML::Element)

          node.namespace_definitions.each do |ns|
            next if ns.href.nil? || ns.href.empty?

            # Check if URI is relative
            if relative_uri?(ns.href)
              raise Canon::Error,
                    "Relative namespace URI not allowed: #{ns.href}"
            end
          end
        end
      end

      # Check if a URI is relative
      def self.relative_uri?(uri)
        # A URI is relative if it doesn't have a scheme
        uri !~ %r{^[a-zA-Z][a-zA-Z0-9+.-]*:}
      end

      # Build XPath data model from Nokogiri document or fragment
      # rubocop:disable Metrics/MethodLength
      def self.build_from_nokogiri(nokogiri_doc, preserve_whitespace: false)
        root = Nodes::RootNode.new

        if nokogiri_doc.respond_to?(:root) && nokogiri_doc.root
          # For Documents (XML, HTML4, HTML5, Moxml): process the root element
          root.add_child(build_element_node(nokogiri_doc.root,
                                            preserve_whitespace: preserve_whitespace))

          # Process PIs and comments outside doc element
          nokogiri_doc.children.each do |child|
            next if child == nokogiri_doc.root
            next if child.is_a?(Nokogiri::XML::DTD)

            node = build_node_from_nokogiri(child,
                                            preserve_whitespace: preserve_whitespace)
            root.add_child(node) if node
          end
        else
          # For DocumentFragments: process all children directly
          # Fragments don't have a single .root, they contain multiple top-level nodes
          nokogiri_doc.children.each do |child|
            next if child.is_a?(Nokogiri::XML::DTD)

            node = build_node_from_nokogiri(child,
                                            preserve_whitespace: preserve_whitespace)
            root.add_child(node) if node
          end
        end

        root
      end

      # Build node from Nokogiri node
      def self.build_node_from_nokogiri(nokogiri_node,
preserve_whitespace: false)
        case nokogiri_node
        when Nokogiri::XML::Element
          build_element_node(nokogiri_node,
                             preserve_whitespace: preserve_whitespace)
        when Nokogiri::XML::Text
          build_text_node(nokogiri_node,
                          preserve_whitespace: preserve_whitespace)
        when Nokogiri::XML::Comment
          build_comment_node(nokogiri_node)
        when Nokogiri::XML::ProcessingInstruction
          build_pi_node(nokogiri_node)
        end
      end

      # Build element node from Nokogiri element
      # rubocop:disable Metrics/MethodLength
      def self.build_element_node(nokogiri_element, preserve_whitespace: false)
        element = Nodes::ElementNode.new(
          name: nokogiri_element.name,
          namespace_uri: nokogiri_element.namespace&.href,
          prefix: nokogiri_element.namespace&.prefix,
        )

        # Build namespace nodes (includes inherited namespaces)
        build_namespace_nodes(nokogiri_element, element)

        # Build attribute nodes
        build_attribute_nodes(nokogiri_element, element)

        # Build child nodes
        nokogiri_element.children.each do |child|
          node = build_node_from_nokogiri(child,
                                          preserve_whitespace: preserve_whitespace)
          element.add_child(node) if node
        end

        element
      end

      # Build namespace nodes for an element
      def self.build_namespace_nodes(nokogiri_element, element)
        # Collect all in-scope namespaces
        namespaces = collect_in_scope_namespaces(nokogiri_element)

        namespaces.each do |prefix, uri|
          ns_node = Nodes::NamespaceNode.new(
            prefix: prefix,
            uri: uri,
          )
          element.add_namespace(ns_node)
        end
      end

      # Collect all in-scope namespaces for an element
      # rubocop:disable Metrics/MethodLength
      def self.collect_in_scope_namespaces(nokogiri_element)
        namespaces = {}

        # Walk up the tree to collect all namespace declarations
        current = nokogiri_element
        while current && !current.is_a?(Nokogiri::XML::Document)
          if current.is_a?(Nokogiri::XML::Element)
            current.namespace_definitions.each do |ns|
              prefix = ns.prefix || ""
              # Only add if not already defined (child overrides parent)
              unless namespaces.key?(prefix)
                namespaces[prefix] = ns.href
              end
            end
          end
          current = current.parent
        end

        # Always include xml namespace
        namespaces["xml"] ||= "http://www.w3.org/XML/1998/namespace"

        namespaces
      end

      # Build attribute nodes for an element
      def self.build_attribute_nodes(nokogiri_element, element)
        nokogiri_element.attributes.each_value do |attr|
          attr_node = Nodes::AttributeNode.new(
            name: attr.name,
            value: attr.value,
            namespace_uri: attr.namespace&.href,
            prefix: attr.namespace&.prefix,
          )
          element.add_attribute(attr_node)
        end
      end

      # Build text node from Nokogiri text node
      def self.build_text_node(nokogiri_text, preserve_whitespace: false)
        # XML text nodes: preserve all content including whitespace
        # Unlike HTML, XML treats all whitespace as significant
        content = nokogiri_text.content

        # Skip empty text nodes between elements (common formatting whitespace)
        # UNLESS preserve_whitespace is true (for structural_whitespace: :strict)
        if !preserve_whitespace && content.strip.empty? && nokogiri_text.parent.is_a?(Nokogiri::XML::Element)
          return nil
        end

        # Nokogiri already handles CDATA conversion and entity resolution
        Nodes::TextNode.new(value: content)
      end

      # Build comment node from Nokogiri comment
      def self.build_comment_node(nokogiri_comment)
        Nodes::CommentNode.new(value: nokogiri_comment.content)
      end

      # Build PI node from Nokogiri PI
      def self.build_pi_node(nokogiri_pi)
        Nodes::ProcessingInstructionNode.new(
          target: nokogiri_pi.name,
          data: nokogiri_pi.content,
        )
      end
    end
  end
end
