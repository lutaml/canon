# frozen_string_literal: true

require "nokogiri"
require_relative "nodes/root_node"
require_relative "nodes/element_node"
require_relative "nodes/namespace_node"
require_relative "nodes/attribute_node"
require_relative "nodes/text_node"
require_relative "nodes/comment_node"
require_relative "nodes/processing_instruction_node"

module Canon
  module Xml
    # Builds Canon::Xml::Node tree using Nokogiri SAX parser
    #
    # This is MUCH faster than DOM parsing + conversion because:
    # 1. No intermediate Nokogiri DOM tree (saves ~60ms)
    # 2. No tree traversal to build Canon (saves ~1200ms)
    # 3. No memory overhead of two complete DOM trees
    #
    # Current (SLOW): XML String → Nokogiri DOM (~60ms) → Canon DOM (~1200ms) = ~1260ms
    # Optimized (FAST): XML String → Nokogiri SAX → Canon DOM (~200ms) = ~200ms
    #
    # Usage:
    #   root = SaxBuilder.parse(xml_string, preserve_whitespace: false)
    #   # root is a Canon::Xml::Nodes::RootNode
    #
    # For C14N, use strip_doctype: true to avoid DTD default attribute expansion:
    #   root = SaxBuilder.parse(xml_string, strip_doctype: true)
    #
    class SaxBuilder < Nokogiri::XML::SAX::Document
      # Parse XML string and return Canon::Xml::Node tree
      #
      # @param xml_string [String] XML content to parse
      # @param preserve_whitespace [Boolean] Whether to preserve whitespace-only text nodes
      # @param strip_doctype [Boolean] Strip DOCTYPE before parsing (for C14N to avoid DTD default attrs)
      # @return [Nodes::RootNode] Root of the data model tree
      def self.parse(xml_string, preserve_whitespace: false,
strip_doctype: false)
        # Strip DOCTYPE to prevent Nokogiri SAX from expanding DTD default attributes
        # This is needed for C14N which should NOT include default attributes from DTD
        # Match multi-line DOCTYPE declarations with nested content
        if strip_doctype
          xml_string = xml_string.gsub(/<!DOCTYPE\s+[^>\[]*(\[[^\]]*\])?\s*>/im,
                                       "")
        end

        builder = new(preserve_whitespace: preserve_whitespace)
        parser = Nokogiri::XML::SAX::Parser.new(builder)
        parser.parse(xml_string)
        builder.result
      end

      # Initialize the SAX builder
      #
      # @param preserve_whitespace [Boolean] Whether to preserve whitespace-only text nodes
      def initialize(preserve_whitespace: false)
        @preserve_whitespace = preserve_whitespace
        @root = Nodes::RootNode.new
        @stack = [@root]
        # Track in-scope namespaces at each level
        # Each entry is a hash of prefix => uri
        @namespace_stack = [build_initial_namespaces]
      end

      # Called when an element starts
      #
      # @param name [String] Element name (may include prefix like "ns:element")
      # @param attrs [Array] Array of [name, value] pairs
      def start_element(name, attrs = [])
        parent = @stack.last

        # Parse namespace from name (prefix:localname or just localname)
        prefix, local_name = parse_qname(name)

        # Separate namespace declarations from regular attributes
        ns_decls, regular_attrs = separate_namespaces(attrs)

        # Check for relative namespace URIs
        ns_decls.each_value do |uri|
          next if uri.nil? || uri.empty?

          if relative_uri?(uri)
            raise Canon::Error,
                  "Relative namespace URI not allowed: #{uri}"
          end
        end

        # Push new namespace scope with declarations
        new_scope = @namespace_stack.last.merge(build_ns_hash(ns_decls))
        @namespace_stack.push(new_scope)

        # Find namespace URI from current scope
        ns_uri = new_scope[prefix.to_s]

        # Create element node
        element = Nodes::ElementNode.new(
          name: local_name,
          namespace_uri: ns_uri,
          prefix: prefix,
        )

        # Add namespace nodes from current scope
        add_namespace_nodes(element, new_scope)

        # Build and add attribute nodes (excluding xmlns declarations)
        add_attribute_nodes(element, regular_attrs)

        parent.add_child(element)
        @stack.push(element)
      end

      # Called when an element ends
      #
      # @param _name [String] Element name (unused)
      def end_element(_name)
        @stack.pop
        @namespace_stack.pop
      end

      # Called for text content
      #
      # @param string [String] Text content
      def characters(string)
        return if string.nil?

        parent = @stack.last

        # Decode numeric character references
        decoded_string = decode_character_references(string)

        # Combine with previous text node if adjacent (SAX can split text content)
        # This MUST happen before whitespace check, because SAX may split "foo "
        # into "foo" and " " callbacks - we need to combine them before deciding
        # whether to skip whitespace
        last_child = parent.children.last
        if last_child&.node_type == :text
          last_child.instance_variable_set(:@value,
                                           last_child.value + decoded_string)
          return
        end

        # Skip whitespace-only text nodes unless:
        # 1. preserve_whitespace is true, OR
        # 2. The content contains CR (from &#xD; entities) which must be preserved for C14N
        if !@preserve_whitespace && decoded_string.strip.empty? && parent.node_type == :element && !decoded_string.include?("\r")
          # Only skip if parent is an element (not root)
          return
        end

        text = Nodes::TextNode.new(value: decoded_string)
        parent.add_child(text)
      end

      # Called for comments
      #
      # @param string [String] Comment content
      def comment(string)
        parent = @stack.last
        comment_node = Nodes::CommentNode.new(value: string)
        parent.add_child(comment_node)
      end

      # Called for processing instructions
      #
      # @param name [String] PI target
      # @param content [String] PI content
      def processing_instruction(name, content)
        parent = @stack.last
        pi = Nodes::ProcessingInstructionNode.new(target: name,
                                                  data: content || "")
        parent.add_child(pi)
      end

      # Return the built tree
      #
      # @return [Nodes::RootNode] Root of the tree
      def result
        # Reorder children so that the document element comes first,
        # followed by PIs and comments outside the document element
        # (C14N requires this ordering)
        reorder_children(@root)
        @root
      end

      # Reorder root children so document element comes first
      # followed by PIs and comments (outside document element)
      def reorder_children(root)
        doc_element = root.children.find { |c| c.node_type == :element }
        return unless doc_element

        other_children = root.children.reject { |c| c.node_type == :element }
        root.instance_variable_set(:@children, [doc_element] + other_children)
      end

      private

      # Build initial namespace scope (includes xml namespace)
      #
      # @return [Hash] Namespace prefix => URI mapping
      def build_initial_namespaces
        {
          "xml" => "http://www.w3.org/XML/1998/namespace",
        }
      end

      # Build namespace hash from declarations array
      #
      # @param ns_decls [Array] Array of [name, value] pairs for namespace declarations
      # @return [Hash] Namespace prefix => URI mapping
      def build_ns_hash(ns_decls)
        result = {}
        ns_decls.each do |name, uri|
          # xmlns="..." for default namespace, xmlns:prefix="..." for prefixed
          prefix = if name == "xmlns"
                     ""
                   else
                     name.sub("xmlns:", "")
                   end
          result[prefix] = uri
        end
        result
      end

      # Parse a QName into prefix and local name
      #
      # @param qname [String] QName like "prefix:local" or "local"
      # @return [Array<(String, String)>] [prefix, local_name] - prefix may be nil
      def parse_qname(qname)
        if qname.include?(":")
          parts = qname.split(":", 2)
          [parts[0], parts[1]]
        else
          [nil, qname]
        end
      end

      # Separate namespace declarations from regular attributes
      #
      # @param attrs [Array] Array of [name, value] pairs
      # @return [Array] Two arrays: [namespace_decls, regular_attrs]
      def separate_namespaces(attrs)
        ns_decls = []
        regular_attrs = []

        attrs.each do |name, value|
          if name == "xmlns" || name.start_with?("xmlns:")
            ns_decls << [name, value]
          else
            regular_attrs << [name, value]
          end
        end

        [ns_decls, regular_attrs]
      end

      # Add namespace nodes to element
      #
      # @param element [Nodes::ElementNode] Element to add namespaces to
      # @param scope [Hash] Current namespace scope
      def add_namespace_nodes(element, scope)
        scope.each do |prefix, uri|
          ns_node = Nodes::NamespaceNode.new(prefix: prefix, uri: uri)
          element.add_namespace(ns_node)
        end
      end

      # Add attribute nodes to element
      #
      # @param element [Nodes::ElementNode] Element to add attributes to
      # @param attrs [Array] Array of [name, value] pairs
      def add_attribute_nodes(element, attrs)
        attrs.each do |attr_name, attr_value|
          attr_prefix, attr_local = parse_qname(attr_name)

          # Find namespace for attribute (if prefixed)
          attr_ns_uri = attr_prefix ? @namespace_stack.last[attr_prefix] : nil

          # Decode numeric character references (e.g., &#38; → &)
          # Nokogiri SAX leaves these as-is, but we need them decoded for C14N
          decoded_value = decode_character_references(attr_value || "")

          attr_node = Nodes::AttributeNode.new(
            name: attr_local,
            value: decoded_value,
            namespace_uri: attr_ns_uri,
            prefix: attr_prefix,
          )
          element.add_attribute(attr_node)
        end
      end

      # Decode numeric character references in a string
      # Handles both &#decimal; and &#xhex; forms
      #
      # @param value [String] String potentially containing character references
      # @return [String] String with character references decoded
      def decode_character_references(value)
        value.gsub(/&#(x?[0-9a-fA-F]+);/) do |match|
          code_str = Regexp.last_match(1)
          code_point = if code_str.start_with?("x")
                         # Hexadecimal: &#xHHHH;
                         code_str[1..].to_i(16)
                       else
                         # Decimal: &#DDDD;
                         code_str.to_i
                       end
          # Convert code point to character (UTF-8)
          [code_point].pack("U")
        rescue StandardError
          # If conversion fails, keep original
          match
        end
      end

      # Check if a URI is relative
      #
      # @param uri [String] URI to check
      # @return [Boolean] true if relative
      def relative_uri?(uri)
        # A URI is relative if it doesn't have a scheme
        uri !~ %r{^[a-zA-Z][a-zA-Z0-9+.-]*:}
      end
    end
  end
end
