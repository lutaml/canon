# frozen_string_literal: true

require "nokogiri"
require_relative "../../xml/namespace_helper"

module Canon
  class DiffFormatter
    module DiffDetailFormatterHelpers
      # Node utility methods
      #
      # Provides helper methods for extracting information from nodes.
      module NodeUtils
        # Get attribute names from a node
        #
        # @param node [Object] Node to extract attributes from
        # @return [Array<String>] Array of attribute names
        def self.get_attribute_names(node)
          return [] unless node

          attrs = if node.respond_to?(:attribute_nodes)
                    node.attribute_nodes
                  elsif node.respond_to?(:attributes)
                    node.attributes
                  elsif node.respond_to?(:[]) && node.respond_to?(:each)
                    # Hash-like node
                    node.keys
                  else
                    []
                  end

          return [] unless attrs

          # Handle different attribute formats
          if attrs.is_a?(Array)
            attrs.map { |attr| attr.respond_to?(:name) ? attr.name : attr.to_s }
          elsif attrs.respond_to?(:keys)
            attrs.keys.map(&:to_s)
          else
            []
          end
        end

        # Find all differing attributes between two nodes
        #
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @return [Array<String>] Array of attribute names with different values
        def self.find_all_differing_attributes(node1, node2)
          return [] unless node1 && node2

          attrs1 = get_attributes_hash(node1)
          attrs2 = get_attributes_hash(node2)

          all_keys = (attrs1.keys | attrs2.keys)

          all_keys.reject do |key|
            attrs1[key.to_s] == attrs2[key.to_s]
          end
        end

        # Get attribute names in order from a node
        #
        # @param node [Object] Node to extract from
        # @return [Array<String>] Ordered array of attribute names
        def self.get_attribute_names_in_order(node)
          return [] unless node

          attrs = if node.respond_to?(:attribute_nodes)
                    node.attribute_nodes
                  elsif node.respond_to?(:attributes)
                    node.attributes
                  else
                    []
                  end

          return [] unless attrs

          if attrs.is_a?(Array)
            attrs.map { |attr| attr.respond_to?(:name) ? attr.name : attr.to_s }
          else
            attrs.keys.map(&:to_s)
          end
        end

        # Get attributes as a hash
        #
        # @param node [Object] Node to extract from
        # @return [Hash] Attributes hash
        def self.get_attributes_hash(node)
          return {} unless node

          attrs = if node.respond_to?(:attribute_nodes)
                    node.attribute_nodes
                  elsif node.respond_to?(:attributes)
                    node.attributes
                  else
                    {}
                  end

          return {} unless attrs

          result = {}
          if attrs.is_a?(Array)
            attrs.each do |attr|
              name = attr.respond_to?(:name) ? attr.name : attr.to_s
              value = attr.respond_to?(:value) ? attr.value : attr.to_s
              result[name] = value
            end
          elsif attrs.respond_to?(:each)
            attrs.each do |key, val|
              name = key.to_s
              value = if val.respond_to?(:value)
                        val.value
                      elsif val.respond_to?(:content)
                        val.content
                      else
                        val.to_s
                      end
              result[name] = value
            end
          end

          result
        end

        # Get attribute value from a node
        #
        # @param node [Object] Node to extract from
        # @param attr_name [String] Attribute name
        # @return [String, nil] Attribute value or nil
        def self.get_attribute_value(node, attr_name)
          return nil unless node && attr_name

          if node.respond_to?(:[])
            value = node[attr_name]
            if value.respond_to?(:value)
              value.value
            elsif value.respond_to?(:content)
              value.content
            elsif value.respond_to?(:to_s)
              value.to_s
            else
              value
            end
          elsif node.respond_to?(:get_attribute)
            attr = node.get_attribute(attr_name)
            attr.respond_to?(:value) ? attr.value : attr
          elsif node.respond_to?(:attribute_nodes)
            attribute_node = node.attribute_nodes.find do |attr|
              attr.name == attr_name.to_s
            end
            attribute_node&.value
          end
        end

        # Get text content from a node
        #
        # @param node [Object] Node to extract from
        # @return [String] Text content
        def self.get_node_text(node)
          return "" unless node

          text = if node.respond_to?(:text)
                   node.text
                 elsif node.respond_to?(:content)
                   node.content
                 elsif node.respond_to?(:inner_text)
                   node.inner_text
                 elsif node.respond_to?(:value)
                   node.value
                 elsif node.respond_to?(:node_info)
                   node.node_info
                 elsif node.respond_to?(:to_s)
                   node.to_s
                 else
                   ""
                 end

          strip_ascii_whitespace(text.to_s)
        end

        # Strip only ASCII whitespace (space, tab, CR, LF) but preserve Unicode
        # whitespace like non-breaking space (\u00A0). Ruby's String#strip removes
        # all Unicode whitespace, which destroys meaningful content like \u00A0.
        #
        # @param str [String] String to strip
        # @return [String] String with leading/trailing ASCII whitespace removed
        ASCII_WHITESPACE_BYTES = [32, 9, 13, 10].freeze # ' ', '\t', '\r', '\n'

        def self.strip_ascii_whitespace(str)
          return "" if str.nil?
          return str if str.empty?

          # Find first non-ASCII-whitespace character position
          first_pos = str.index(/[^ \t\r\n]/)
          return "" unless first_pos

          # Find last non-ASCII-whitespace character position (from end)
          # Use reverse and index, then convert back to forward position
          reversed_pos = str.reverse.index(/[^ \t\r\n]/)
          last_pos = str.length - 1 - reversed_pos

          str[first_pos..last_pos]
        end

        # Get element name for display
        #
        # @param node [Object] Node to get name from
        # @return [String] Element name
        def self.get_element_name_for_display(node)
          return "" unless node

          # Handle TextNode specially since it doesn't respond to :name
          if node.is_a?(Canon::Xml::Nodes::TextNode)
            return "text"
          end

          # Handle CommentNode specially since it doesn't respond to :name
          if node.is_a?(Canon::Xml::Nodes::CommentNode)
            return "comment"
          end

          if node.respond_to?(:name)
            node.name.to_s
          else
            node.class.name
          end
        end

        # Get namespace URI for display
        #
        # @param node [Object] Node to get namespace from
        # @return [String] Namespace URI
        def self.get_namespace_uri_for_display(node)
          return "" unless node

          if node.respond_to?(:namespace_uri)
            node.namespace_uri.to_s
          elsif node.respond_to?(:namespace)
            ns = node.namespace
            ns.respond_to?(:href) ? ns.href.to_s : ""
          else
            ""
          end
        end

        # Format node briefly for display
        #
        # @param node [Object] Node to format
        # @return [String] Brief node description
        def self.format_node_brief(node)
          return "" unless node

          name = get_element_name_for_display(node)
          text = get_node_text(node)

          if text && !text.empty?
            "#{name}(\"#{text}\")"
          else
            name
          end
        end

        # Serialize a node tree as compact XML for display.
        #
        # Produces a human-readable inline XML string without namespace
        # declarations and without indentation — suitable for use in Semantic
        # Diff Report entries.  Handles both +Canon::Xml::Nodes+ types and
        # Nokogiri XML/HTML nodes (the html DOM comparison path uses
        # Nokogiri nodes, so element-structure diffs originating there must
        # be rendered structurally too — see issue #120).  For any other
        # node type, falls back to +get_node_text+.
        #
        # @param node [Object] Node to serialize
        # @return [String] Compact XML string
        def self.serialize_node_compact(node)
          require "cgi"
          return "" unless node

          case node
          when Canon::Xml::Nodes::TextNode
            CGI.escapeHTML(node.value.to_s)
          when Canon::Xml::Nodes::ElementNode
            tag = node.name.to_s
            attrs = node.attribute_nodes.map do |attr|
              attr_name  = attr.respond_to?(:name)  ? attr.name.to_s  : attr.to_s
              attr_value = attr.respond_to?(:value) ? attr.value.to_s : ""
              " #{attr_name}=\"#{CGI.escapeHTML(attr_value)}\""
            end.join
            children_xml = node.children.map do |c|
              serialize_node_compact(c)
            end.join
            if children_xml.empty?
              "<#{tag}#{attrs}/>"
            else
              "<#{tag}#{attrs}>#{children_xml}</#{tag}>"
            end
          when Canon::Xml::Nodes::CommentNode
            text = node.respond_to?(:value) ? node.value.to_s : ""
            "<!--#{CGI.escapeHTML(text)}-->"
          when Nokogiri::XML::Text, Nokogiri::XML::CDATA
            CGI.escapeHTML(node.content.to_s)
          when Nokogiri::XML::Comment
            "<!--#{CGI.escapeHTML(node.content.to_s)}-->"
          when Nokogiri::XML::Element
            tag = node.name.to_s
            attrs = node.attribute_nodes.map do |a|
              " #{a.name}=\"#{CGI.escapeHTML(a.value.to_s)}\""
            end.join
            children_xml = node.children.map do |c|
              serialize_node_compact(c)
            end.join
            if children_xml.empty?
              "<#{tag}#{attrs}/>"
            else
              "<#{tag}#{attrs}>#{children_xml}</#{tag}>"
            end
          else
            # Unknown node types — fall back to text extraction
            get_node_text(node)
          end
        end

        # Serialize a node's open tag only — name + attributes, no children,
        # no closing tag.  Used by +format_text_content_one_sided+ to render
        # a brief parent-element context hint (e.g. +<div id="A">+) for a
        # one-sided text diff, instead of the full ancestor subtree that
        # +serialize_node_compact+ would produce.  See lutaml/canon#125.
        #
        # @param node [Object] Element node to serialize
        # @return [String] Open-tag string, or "" for non-elements / nil
        def self.serialize_open_tag(node)
          require "cgi"
          return "" unless node

          case node
          when Canon::Xml::Nodes::ElementNode
            tag = node.name.to_s
            attrs = node.attribute_nodes.map do |attr|
              " #{attr.name}=\"#{CGI.escapeHTML(attr.value.to_s)}\""
            end.join
            "<#{tag}#{attrs}>"
          when Nokogiri::XML::Element
            tag = node.name.to_s
            attrs = node.attribute_nodes.map do |a|
              " #{a.name}=\"#{CGI.escapeHTML(a.value.to_s)}\""
            end.join
            "<#{tag}#{attrs}>"
          else
            ""
          end
        end

        # Return the raw text content of a text node without stripping
        # whitespace.  +get_node_text+ strips ASCII whitespace, which
        # destroys whitespace-only payloads that callers (e.g. one-sided
        # text-content diff rendering) need to display verbatim.
        #
        # @param node [Object] Text node
        # @return [String] Raw text content, or "" if not a text-bearing node
        def self.raw_text_value(node)
          return "" unless node

          case node
          when Canon::Xml::Node
            node.value.to_s
          when Nokogiri::XML::Node
            node.content.to_s
          else
            ""
          end
        end

        # Return the best display string for a node.
        #
        # When +compact: true+ and the node is a Canon ElementNode, returns a
        # compact XML serialization (e.g. +<strong>Annex</strong>+) instead of
        # the +node_info+ description string that +get_node_text+ would produce.
        # In all other cases, delegates to +get_node_text+.
        #
        # @param node [Object] Node to display
        # @param compact [Boolean] Whether to use compact XML for element nodes
        # @return [String] Display string
        def self.node_to_display(node, compact: false)
          if compact && node.is_a?(Canon::Xml::Nodes::ElementNode)
            serialize_node_compact(node)
          else
            get_node_text(node)
          end
        end

        # Return the parent of a node, or nil, regardless of the node API.
        #
        # Canon::Xml nodes expose +parent+; some Nokogiri-shaped nodes expose
        # +parent_node+.  This helper abstracts over both.
        #
        # @param node [Object] Node to query
        # @return [Object, nil] Parent node or nil
        def self.parent_of(node)
          return nil unless node

          if node.respond_to?(:parent)
            node.parent
          elsif node.respond_to?(:parent_node)
            node.parent_node
          end
        end

        # Check if node is inside a preserve-whitespace element
        #
        # @param node [Object] Node to check
        # @return [Boolean] true if inside preserve element
        def self.inside_preserve_element?(node)
          return false unless node

          preserve_elements = %w[pre code textarea script style]

          # Check the node itself
          if node.respond_to?(:name) && preserve_elements.include?(node.name.to_s.downcase)
            return true
          end

          # Check ancestors
          current = node
          while current
            if current.respond_to?(:parent)
              current = current.parent
            elsif current.respond_to?(:parent_node)
              current = current.parent_node
            else
              break
            end

            next unless current

            if current.respond_to?(:name) && preserve_elements.include?(current.name.to_s.downcase)
              return true
            end
          end

          false
        end
      end
    end
  end
end
