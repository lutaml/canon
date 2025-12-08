# frozen_string_literal: true

require "nokogiri"
require_relative "../data_model"
require_relative "../xml/nodes/root_node"
require_relative "../xml/nodes/element_node"
require_relative "../xml/nodes/namespace_node"
require_relative "../xml/nodes/attribute_node"
require_relative "../xml/nodes/text_node"
require_relative "../xml/nodes/comment_node"
require_relative "../xml/nodes/processing_instruction_node"

module Canon
  module Html
    # Builds XPath data model from HTML
    # HTML-specific parsing with lowercase element/attribute names,
    # whitespace-sensitive element handling, and fragment parsing
    class DataModel < Canon::DataModel
      # Build XPath data model from HTML string
      #
      # @param html_string [String] HTML content to parse
      # @param version [Symbol] HTML version (:html4 or :html5)
      # @return [Canon::Xml::Nodes::RootNode] Root of the data model tree
      def self.from_html(html_string, version: :html4)
        # Detect if this is a full document (has <html> tag) or fragment
        # Full documents should use document parser to preserve structure
        # Fragments should use fragment parser to avoid adding implicit wrappers
        is_full_document = html_string.match?(/<html[\s>]/i)

        # Parse with Nokogiri using appropriate parser
        doc = if is_full_document
                # Full document - use fragment parser to avoid Nokogiri's phantom tag insertion
                # The fragment parser avoids auto-inserted meta tags in HTML4
                if version == :html5
                  Nokogiri::HTML5.fragment(html_string)
                else
                  Nokogiri::HTML4.fragment(html_string)
                end
              elsif version == :html5
                # Fragment - use fragment parser to avoid implicit wrappers
                Nokogiri::HTML5.fragment(html_string)
              else
                Nokogiri::HTML4.fragment(html_string)
              end

        # HTML doesn't have strict namespace requirements like XML,
        # so skip the relative namespace URI check

        # Convert to XPath data model (reuse XML infrastructure)
        build_from_nokogiri(doc)
      end

      # Alias for compatibility
      def self.parse(html_string, version: :html4)
        from_html(html_string, version: version)
      end

      # Serialize HTML node to string
      def self.serialize(node)
        # HTML nodes use the same serialization as XML
        # Delegate to XML serialization implementation
        require_relative "../xml/data_model"
        Canon::Xml::DataModel.serialize(node)
      end

      # Build XPath data model from Nokogiri document or fragment
      def self.build_from_nokogiri(nokogiri_doc)
        root = Canon::Xml::Nodes::RootNode.new

        if nokogiri_doc.respond_to?(:root) && nokogiri_doc.root
          # For Documents (HTML4, HTML5): process the root element
          root.add_child(build_element_node(nokogiri_doc.root))

          # Process PIs and comments outside doc element
          nokogiri_doc.children.each do |child|
            next if child == nokogiri_doc.root
            next if child.is_a?(Nokogiri::XML::DTD)

            node = build_node_from_nokogiri(child)
            root.add_child(node) if node
          end
        else
          # For DocumentFragments: process all children directly
          # Fragments don't have a single .root, they contain multiple top-level nodes
          nokogiri_doc.children.each do |child|
            next if child.is_a?(Nokogiri::XML::DTD)

            node = build_node_from_nokogiri(child)
            root.add_child(node) if node
          end
        end

        root
      end

      # Build node from Nokogiri node
      def self.build_node_from_nokogiri(nokogiri_node)
        case nokogiri_node
        when Nokogiri::XML::Element
          build_element_node(nokogiri_node)
        when Nokogiri::XML::Text
          build_text_node(nokogiri_node)
        when Nokogiri::XML::Comment
          build_comment_node(nokogiri_node)
        when Nokogiri::XML::ProcessingInstruction
          build_pi_node(nokogiri_node)
        end
      end

      # Build element node from Nokogiri element
      def self.build_element_node(nokogiri_element)
        element = Canon::Xml::Nodes::ElementNode.new(
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
          node = build_node_from_nokogiri(child)
          element.add_child(node) if node
        end

        element
      end

      # Build namespace nodes for an element
      def self.build_namespace_nodes(nokogiri_element, element)
        # Collect all in-scope namespaces
        namespaces = collect_in_scope_namespaces(nokogiri_element)

        namespaces.each do |prefix, uri|
          ns_node = Canon::Xml::Nodes::NamespaceNode.new(
            prefix: prefix,
            uri: uri,
          )
          element.add_namespace(ns_node)
        end
      end

      # Collect all in-scope namespaces for an element
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
        nokogiri_element.attributes.each do |name, attr|
          next if name.start_with?("xmlns")

          attr_node = Canon::Xml::Nodes::AttributeNode.new(
            name: attr.name,
            value: attr.value,
            namespace_uri: attr.namespace&.href,
            prefix: attr.namespace&.prefix,
          )
          element.add_attribute(attr_node)
        end
      end

      # Build text node from Nokogiri text node
      # HTML-specific: handles whitespace-sensitive elements (pre, code, textarea, script, style)
      def self.build_text_node(nokogiri_text)
        # Skip text nodes that are only whitespace between elements
        # EXCEPT in whitespace-sensitive elements (pre, code, textarea, script, style)
        # where whitespace is semantically significant
        content = nokogiri_text.content

        if content.strip.empty? && nokogiri_text.parent.is_a?(Nokogiri::XML::Element)
          # Check if parent is whitespace-sensitive
          parent_name = nokogiri_text.parent.name.downcase
          whitespace_sensitive_tags = %w[pre code textarea script style]

          # Skip whitespace-only text UNLESS in whitespace-sensitive element
          return nil unless whitespace_sensitive_tags.include?(parent_name)
        end

        # Nokogiri already handles CDATA conversion and entity resolution
        Canon::Xml::Nodes::TextNode.new(value: content)
      end

      # Build comment node from Nokogiri comment
      def self.build_comment_node(nokogiri_comment)
        Canon::Xml::Nodes::CommentNode.new(value: nokogiri_comment.content)
      end

      # Build PI node from Nokogiri PI
      def self.build_pi_node(nokogiri_pi)
        Canon::Xml::Nodes::ProcessingInstructionNode.new(
          target: nokogiri_pi.name,
          data: nokogiri_pi.content,
        )
      end

      class << self
        private :build_from_nokogiri, :build_node_from_nokogiri,
                :build_element_node, :build_namespace_nodes,
                :collect_in_scope_namespaces, :build_attribute_nodes,
                :build_text_node, :build_comment_node, :build_pi_node
      end
    end
  end
end
