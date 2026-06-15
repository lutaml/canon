# frozen_string_literal: true

require "cgi"

module Canon
  class DiffFormatter
    module DiffDetailFormatterHelpers
      # Node utility methods for the diff detail formatter.
      #
      # All node queries delegate to NodeInspector / XmlParsing.
      # No respond_to? — types are known at every call site.
      module NodeUtils
        # --- Attribute extraction ---

        def self.get_attribute_names(node)
          extract_attribute_names(node)
        end

        def self.get_attribute_names_in_order(node)
          extract_attribute_names(node)
        end

        def self.find_all_differing_attributes(node1, node2)
          return [] unless node1 && node2

          attrs1 = get_attributes_hash(node1)
          attrs2 = get_attributes_hash(node2)

          (attrs1.keys | attrs2.keys).reject do |key|
            attrs1[key.to_s] == attrs2[key.to_s]
          end
        end

        def self.get_attributes_hash(node)
          return {} unless node

          case node
          when Canon::Xml::Nodes::ElementNode
            node.attribute_nodes.to_h { |a| [a.name.to_s, a.value.to_s] }
          else
            backend_attributes_hash(node)
          end
        end

        def self.get_attribute_value(node, attr_name)
          return nil unless node && attr_name

          case node
          when Canon::Xml::Nodes::ElementNode
            attr = node.attribute_nodes.find { |a| a.name == attr_name.to_s }
            attr&.value
          else
            XmlParsing.attribute_value(node, attr_name)
          end
        end

        # --- Text / name / namespace ---

        def self.get_node_text(node)
          return "" unless node

          strip_ascii_whitespace(Canon::Comparison::NodeInspector.text_content(node).to_s)
        end

        ASCII_WHITESPACE_PATTERN = /[ \t\r\n]/

        def self.strip_ascii_whitespace(str)
          return "" if str.nil?
          return str if str.empty?

          first_pos = str.index(/[^ \t\r\n]/)
          return "" unless first_pos

          reversed_pos = str.reverse.index(/[^ \t\r\n]/)
          last_pos = str.length - 1 - reversed_pos

          str[first_pos..last_pos]
        end

        def self.get_element_name_for_display(node)
          return "" unless node

          case node
          when Canon::Xml::Nodes::TextNode
            "text"
          when Canon::Xml::Nodes::CommentNode
            "comment"
          else
            Canon::Comparison::NodeInspector.name(node).to_s
          end
        end

        def self.get_namespace_uri_for_display(node)
          return "" unless node

          Canon::Comparison::NodeInspector.namespace_uri(node).to_s
        end

        # --- Display helpers ---

        def self.format_node_brief(node)
          return "" unless node

          name = get_element_name_for_display(node)
          text = get_node_text(node)

          text && !text.empty? ? "#{name}(\"#{text}\")" : name
        end

        def self.node_to_display(node, compact: false)
          if compact && node.is_a?(Canon::Xml::Nodes::ElementNode)
            serialize_node_compact(node)
          else
            get_node_text(node)
          end
        end

        # --- Serialization ---

        def self.serialize_node_compact(node)
          return "" unless node

          case node
          when Canon::Xml::Nodes::TextNode
            CGI.escapeHTML(node.value.to_s)
          when Canon::Xml::Nodes::CommentNode
            "<!--#{CGI.escapeHTML(node.value.to_s)}-->"
          when Canon::Xml::Nodes::ElementNode
            serialize_element_compact(node)
          else
            serialize_backend_node_compact(node)
          end
        end

        def self.serialize_open_tag(node)
          return "" unless node

          case node
          when Canon::Xml::Nodes::ElementNode
            tag = node.name.to_s
            attrs = node.attribute_nodes.map do |a|
              " #{a.name}=\"#{CGI.escapeHTML(a.value.to_s)}\""
            end.join
            "<#{tag}#{attrs}>"
          else
            serialize_backend_open_tag(node)
          end
        end

        def self.raw_text_value(node)
          return "" unless node

          Canon::Comparison::NodeInspector.text_content(node).to_s
        end

        # --- Traversal ---

        def self.parent_of(node)
          Canon::Comparison::NodeInspector.parent(node)
        end

        def self.inside_preserve_element?(node)
          return false unless node

          preserve_elements = %w[pre code textarea script style]

          current = node
          while current
            name = Canon::Comparison::NodeInspector.name(current)
            return true if name && preserve_elements.include?(name.to_s.downcase)

            parent = Canon::Comparison::NodeInspector.parent(current)
            break if parent.nil? || parent == current

            current = parent
          end

          false
        end

        class << self
          private

          def extract_attribute_names(node)
            return [] unless node

            case node
            when Canon::Xml::Nodes::ElementNode
              node.attribute_nodes.map(&:name)
            else
              attrs = XmlParsing.attributes(node)
              return [] unless attrs
              return attrs.map { |a| a.name.to_s } if attrs.is_a?(Array)

              attrs.keys.map(&:to_s)
            end
          end

          def backend_attributes_hash(node)
            attrs = XmlParsing.attributes(node)
            return {} unless attrs

            if attrs.is_a?(Array)
              attrs.each_with_object({}) do |attr, h|
                name = attr.is_a?(Canon::Xml::Nodes::AttributeNode) ? attr.name : XmlParsing.name(attr).to_s
                value = attr.is_a?(Canon::Xml::Nodes::AttributeNode) ? attr.value : XmlParsing.text_content(attr).to_s
                h[name.to_s] = value
              end
            else
              attrs.each_with_object({}) do |(key, val), h|
                h[key.to_s] =
                  val.is_a?(String) ? val : XmlParsing.text_content(val).to_s
              end
            end
          end

          def serialize_element_compact(element_node)
            tag = element_node.name.to_s
            attrs = element_node.attribute_nodes.map do |a|
              " #{a.name}=\"#{CGI.escapeHTML(a.value.to_s)}\""
            end.join
            children_xml = element_node.children.map do |c|
              serialize_node_compact(c)
            end.join
            children_xml.empty? ? "<#{tag}#{attrs}/>" : "<#{tag}#{attrs}>#{children_xml}</#{tag}>"
          end

          def serialize_backend_node_compact(node)
            if XmlBackend.nokogiri? && node.is_a?(Nokogiri::XML::Node)
              serialize_nokogiri_node_compact(node)
            elsif node.is_a?(Canon::Xml::Node)
              serialize_node_compact(node)
            else
              get_node_text(node)
            end
          end

          def serialize_nokogiri_node_compact(node)
            case node
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
              children_xml.empty? ? "<#{tag}#{attrs}/>" : "<#{tag}#{attrs}>#{children_xml}</#{tag}>"
            else
              get_node_text(node)
            end
          end

          def serialize_backend_open_tag(node)
            if XmlBackend.nokogiri? && node.is_a?(Nokogiri::XML::Element)
              tag = node.name.to_s
              attrs = node.attribute_nodes.map do |a|
                " #{a.name}=\"#{CGI.escapeHTML(a.value.to_s)}\""
              end.join
              "<#{tag}#{attrs}>"
            else
              ""
            end
          end
        end
      end
    end
  end
end
