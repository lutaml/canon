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
        # Normalize encoding before parsing
        normalized_xml = normalize_encoding(xml_string)

        # Parse with Nokogiri
        doc = Nokogiri::XML(normalized_xml, &:nonet)

        # Check for relative namespace URIs (prohibited by C14N 1.1)
        check_for_relative_namespace_uris(doc)

        # Convert to XPath data model
        build_from_nokogiri(doc, preserve_whitespace: preserve_whitespace)
      end

      # Normalize XML string encoding to UTF-8
      #
      # Handles cases where:
      # 1. The XML declaration specifies an encoding that doesn't match the actual encoding
      # 2. The string's internal encoding is non-UTF-8 (without a declaration)
      #
      # For case 1, we check if the declared encoding matches the actual bytes.
      # If bytes are valid UTF-8 despite the declaration, we update the declaration to UTF-8.
      #
      # @param xml_string [String] XML string to normalize
      # @return [String] Normalized XML string with UTF-8 encoding
      def self.normalize_encoding(xml_string)
        return xml_string unless xml_string.is_a?(String)

        # Extract declared encoding from XML declaration
        declared_encoding = extract_xml_encoding(xml_string)

        if declared_encoding
          # Case 1: XML has a declaration
          if declared_encoding.upcase != "UTF-8"
            # Check if bytes are actually valid UTF-8 despite the declaration
            utf8_reinterpreted = try_utf8_reinterpretation(xml_string)
            if utf8_reinterpreted
              # Bytes are valid UTF-8 - update declaration to UTF-8
              return update_xml_declaration(xml_string, "UTF-8")
            end

            # Bytes aren't valid UTF-8 - must really be in declared encoding
            return transcode_to_utf8(xml_string, declared_encoding)
          end
        elsif xml_string.encoding.name != "UTF-8"
          # Case 2: No declaration but string encoding is non-UTF-8
          # First, try to re-interpret bytes as UTF-8 (handles mislabeled strings)
          reinterpreted = try_utf8_reinterpretation(xml_string)
          return reinterpreted if reinterpreted

          # If re-interpretation fails, try transcoding with the labeled encoding
          return transcode_to_utf8(xml_string, xml_string.encoding.name)
        end

        xml_string
      end

      # Update the encoding declaration in an XML string
      #
      # @param xml_string [String] XML string
      # @param new_encoding [String] New encoding to declare
      # @return [String] XML string with updated declaration
      def self.update_xml_declaration(xml_string, new_encoding)
        xml_string.sub(/\bencoding\s*=\s*["'][^"']+["']/i) do |_match|
          %(encoding="#{new_encoding}")
        end
      end

      # Transcode string to UTF-8
      #
      # @param xml_string [String] String to transcode
      # @param source_encoding [String] Source encoding to interpret bytes as
      # @return [String] UTF-8 transcoded string
      def self.transcode_to_utf8(xml_string, source_encoding)
        # First, check if the bytes are actually valid UTF-8 despite the declared encoding
        # If so, just re-interpret as UTF-8 (common case: declaration is wrong)
        if source_encoding != "UTF-8"
          # Force the bytes to be interpreted as the declared encoding, then check validity
          forced = xml_string.dup.force_encoding(source_encoding)
          if forced.valid_encoding?
            # Now check if the same bytes are valid UTF-8
            utf8_check = xml_string.dup.force_encoding("UTF-8")
            if utf8_check.valid_encoding?
              # Bytes are valid UTF-8 - the declaration is likely wrong
              # Return the string as UTF-8 (already is)
              return xml_string.dup.force_encoding("UTF-8")
            end

            # Bytes aren't valid UTF-8, so they must really be in source_encoding
            # Proceed with transcoding
            return forced.encode("UTF-8", source_encoding,
                                 invalid: :replace,
                                 undef: :replace,
                                 replace: "?")
          end
        end

        # Already UTF-8 or transcoding failed, return as-is
        xml_string.dup.force_encoding("UTF-8")
      rescue EncodingError
        xml_string
      end

      # Attempt to re-interpret string as UTF-8 if bytes are valid UTF-8
      #
      # This handles the case where a string was incorrectly labeled with a different
      # encoding (e.g., `.encode("Shift_JIS")` on a UTF-8 string) but the actual
      # bytes are valid UTF-8.
      #
      # @param xml_string [String] XML string to check
      # @return [String, nil] UTF-8 re-interpreted string, or nil if not possible
      def self.try_utf8_reinterpretation(xml_string)
        return xml_string if xml_string.encoding.name == "UTF-8"

        # Try forcing to UTF-8 and see if it's valid
        forced = xml_string.dup.force_encoding("UTF-8")
        return forced if forced.valid_encoding?

        nil
      end

      # Extract encoding from XML declaration
      #
      # @param xml_string [String] XML string
      # @return [String, nil] Declared encoding or nil if not found
      def self.extract_xml_encoding(xml_string)
        # Match XML declaration with encoding attribute
        # Handles: <?xml version="1.0" encoding="UTF-8"?>
        # and: <?xml version='1.0' encoding='UTF-8'?>
        #
        # Use binary encoding to avoid encoding compatibility issues
        # when the string has non-ASCII compatible encoding (e.g., UTF-16)
        binary_string = xml_string.dup.force_encoding("BINARY")
        if binary_string =~ /\A\s*<\?xml[^>]*\bencoding\s*=\s*["']([^"']+)["'][^>]*\?>/i
          return Regexp.last_match(1)
        end

        nil
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

        # Capture original text with entity references preserved.
        # nokogiri_text.to_xml returns the serialized text node which preserves
        # entity forms like &#x201C; instead of the decoded character U+201C.
        original = nokogiri_text.to_xml

        # Nokogiri already handles CDATA conversion and entity resolution
        Nodes::TextNode.new(value: content, original: original)
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
