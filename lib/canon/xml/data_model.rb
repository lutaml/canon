# frozen_string_literal: true

require "nokogiri" unless RUBY_ENGINE == "opal"
require "set"
require_relative "../data_model"
require_relative "../xml_backend"
require_relative "../xml_parsing"
require_relative "nodes/root_node"
require_relative "nodes/element_node"
require_relative "nodes/namespace_node"
require_relative "nodes/attribute_node"
require_relative "nodes/text_node"
require_relative "nodes/comment_node"
require_relative "nodes/processing_instruction_node"

module Canon
  module Xml
    class DataModel < Canon::DataModel
      def self.from_xml(xml_string, preserve_whitespace: false)
        normalized_xml = normalize_encoding(xml_string)

        if Canon::XmlBackend.nokogiri?
          from_nokogiri_xml(normalized_xml,
                            preserve_whitespace: preserve_whitespace)
        else
          from_moxml_xml(normalized_xml,
                         preserve_whitespace: preserve_whitespace)
        end
      end

      def self.normalize_encoding(xml_string)
        return xml_string unless xml_string.is_a?(String)

        declared_encoding = extract_xml_encoding(xml_string)

        if declared_encoding
          if declared_encoding.upcase != "UTF-8"
            utf8_reinterpreted = try_utf8_reinterpretation(xml_string)
            if utf8_reinterpreted
              return update_xml_declaration(xml_string,
                                            "UTF-8")
            end

            return transcode_to_utf8(xml_string, declared_encoding)
          end
        elsif xml_string.encoding.name != "UTF-8"
          reinterpreted = try_utf8_reinterpretation(xml_string)
          return reinterpreted if reinterpreted

          return transcode_to_utf8(xml_string, xml_string.encoding.name)
        end

        xml_string
      end

      def self.update_xml_declaration(xml_string, new_encoding)
        xml_string.sub(/\bencoding\s*=\s*["'][^"']+["']/i) do |_match|
          %(encoding="#{new_encoding}")
        end
      end

      def self.transcode_to_utf8(xml_string, source_encoding)
        if source_encoding != "UTF-8"
          forced = xml_string.dup.force_encoding(source_encoding)
          if forced.valid_encoding?
            utf8_check = xml_string.dup.force_encoding("UTF-8")
            if utf8_check.valid_encoding?
              return xml_string.dup.force_encoding("UTF-8")
            end

            return forced.encode("UTF-8", source_encoding,
                                 invalid: :replace,
                                 undef: :replace,
                                 replace: "?")
          end
        end

        xml_string.dup.force_encoding("UTF-8")
      rescue EncodingError
        xml_string
      end

      def self.try_utf8_reinterpretation(xml_string)
        return xml_string if xml_string.encoding.name == "UTF-8"

        forced = xml_string.dup.force_encoding("UTF-8")
        return forced if forced.valid_encoding?

        nil
      end

      def self.extract_xml_encoding(xml_string)
        binary_string = xml_string.dup.force_encoding("BINARY")
        if binary_string =~ /\A\s*<\?xml[^>]*\bencoding\s*=\s*["']([^"']+)["'][^>]*\?>/i
          return Regexp.last_match(1)
        end

        nil
      end

      def self.parse(xml_string)
        from_xml(xml_string)
      end

      def self.serialize(node)
        node.to_s
      end

      def self.relative_uri?(uri)
        uri !~ %r{^[a-zA-Z][a-zA-Z0-9+.-]*:}
      end

      # --- Nokogiri path ---

      def self.from_nokogiri_xml(xml_string, preserve_whitespace:)
        doc = Nokogiri::XML(xml_string, &:nonet)
        check_for_relative_namespace_uris(doc)
        result = build_from_nokogiri(doc,
                                     preserve_whitespace: preserve_whitespace)
        errors = Array(doc.errors).map(&:to_s)
        result.parse_errors = errors if errors.any?
        result
      end

      def self.check_for_relative_namespace_uris(doc)
        doc.traverse do |node|
          next unless node.is_a?(Nokogiri::XML::Element)

          node.namespace_definitions.each do |ns|
            next if ns.href.nil? || ns.href.empty?
            if relative_uri?(ns.href)
              raise Canon::Error,
                    "Relative namespace URI not allowed: #{ns.href}"
            end
          end
        end
      end

      def self.build_from_nokogiri(nokogiri_doc, preserve_whitespace: false)
        root = Nodes::RootNode.new

        if nokogiri_doc.is_a?(Nokogiri::XML::Document) && nokogiri_doc.root
          root.add_child(build_element_node(nokogiri_doc.root,
                                            preserve_whitespace: preserve_whitespace))
          nokogiri_doc.children.each do |child|
            next if child == nokogiri_doc.root
            next if child.is_a?(Nokogiri::XML::DTD)

            node = build_node_from_nokogiri(child,
                                            preserve_whitespace: preserve_whitespace)
            root.add_child(node) if node
          end
        else
          nokogiri_doc.children.each do |child|
            next if child.is_a?(Nokogiri::XML::DTD)

            node = build_node_from_nokogiri(child,
                                            preserve_whitespace: preserve_whitespace)
            root.add_child(node) if node
          end
        end

        root
      end

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

      def self.build_element_node(nokogiri_element, preserve_whitespace: false)
        element = Nodes::ElementNode.new(
          name: nokogiri_element.name,
          namespace_uri: nokogiri_element.namespace&.href,
          prefix: nokogiri_element.namespace&.prefix,
        )

        build_namespace_nodes(nokogiri_element, element)
        build_attribute_nodes(nokogiri_element, element)

        nokogiri_element.children.each do |child|
          node = build_node_from_nokogiri(child,
                                          preserve_whitespace: preserve_whitespace)
          element.add_child(node) if node
        end

        element
      end

      def self.build_namespace_nodes(nokogiri_element, element)
        namespaces = collect_in_scope_namespaces(nokogiri_element)

        namespaces.each do |prefix, uri|
          ns_node = Nodes::NamespaceNode.new(
            prefix: prefix,
            uri: uri,
          )
          element.add_namespace(ns_node)
        end
      end

      def self.collect_in_scope_namespaces(nokogiri_element)
        namespaces = {}

        current = nokogiri_element
        while current && !current.is_a?(Nokogiri::XML::Document)
          if current.is_a?(Nokogiri::XML::Element)
            current.namespace_definitions.each do |ns|
              prefix = ns.prefix || ""
              unless namespaces.key?(prefix)
                namespaces[prefix] = ns.href
              end
            end
          end
          current = current.parent
        end

        namespaces["xml"] ||= "http://www.w3.org/XML/1998/namespace"

        namespaces
      end

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

      def self.build_text_node(nokogiri_text, preserve_whitespace: false)
        content = nokogiri_text.content

        if !preserve_whitespace && content.strip.empty? && nokogiri_text.parent.is_a?(Nokogiri::XML::Element)
          return nil
        end

        original = nokogiri_text.to_xml
        Nodes::TextNode.new(value: content, original: original)
      end

      def self.build_comment_node(nokogiri_comment)
        Nodes::CommentNode.new(value: nokogiri_comment.content)
      end

      def self.build_pi_node(nokogiri_pi)
        Nodes::ProcessingInstructionNode.new(
          target: nokogiri_pi.name,
          data: nokogiri_pi.content,
        )
      end

      # --- Moxml path ---

      def self.from_moxml_xml(xml_string, preserve_whitespace:)
        doc = Canon::XmlParsing.parse(xml_string)
        build_from_moxml(doc, preserve_whitespace: preserve_whitespace)
      end

      def self.build_from_moxml(moxml_doc, preserve_whitespace: false)
        root = Nodes::RootNode.new

        if moxml_doc.is_a?(Moxml::Document) && moxml_doc.root
          root.add_child(build_moxml_element_node(moxml_doc.root,
                                                  preserve_whitespace: preserve_whitespace))
        end

        root
      end

      def self.build_moxml_node(node, preserve_whitespace: false)
        case node
        when Moxml::Element
          build_moxml_element_node(node,
                                   preserve_whitespace: preserve_whitespace)
        when Moxml::Text
          build_moxml_text_node(node, preserve_whitespace: preserve_whitespace)
        when Moxml::Comment
          build_moxml_comment_node(node)
        when Moxml::ProcessingInstruction
          build_moxml_pi_node(node)
        end
      end

      def self.build_moxml_element_node(moxml_element,
preserve_whitespace: false)
        ns = moxml_element.namespace
        element = Nodes::ElementNode.new(
          name: moxml_element.name,
          namespace_uri: ns&.uri,
          prefix: ns&.prefix,
        )

        build_moxml_namespace_nodes(moxml_element, element)
        build_moxml_attribute_nodes(moxml_element, element)

        moxml_element.children.each do |child|
          node = build_moxml_node(child,
                                  preserve_whitespace: preserve_whitespace)
          element.add_child(node) if node
        end

        element
      end

      def self.build_moxml_namespace_nodes(moxml_element, element)
        moxml_element.namespace_definitions.each do |ns|
          ns_node = Nodes::NamespaceNode.new(
            prefix: ns.prefix || "",
            uri: ns.uri,
          )
          element.add_namespace(ns_node)
        end

        unless element.namespace_nodes.any? do |n|
          n.prefix == "xml"
        end
          element.add_namespace(Nodes::NamespaceNode.new(
                                  prefix: "xml",
                                  uri: "http://www.w3.org/XML/1998/namespace",
                                ))
        end
      end

      def self.build_moxml_attribute_nodes(moxml_element, element)
        moxml_element.attributes.each do |attr|
          attr_node = Nodes::AttributeNode.new(
            name: attr.name,
            value: attr.value,
          )
          element.add_attribute(attr_node)
        end
      end

      def self.build_moxml_text_node(moxml_text, preserve_whitespace: false)
        content = moxml_text.content

        if !preserve_whitespace && content.strip.empty? && moxml_text.parent.is_a?(Moxml::Element)
          return nil
        end

        Nodes::TextNode.new(value: content, original: content)
      end

      def self.build_moxml_comment_node(moxml_comment)
        Nodes::CommentNode.new(value: moxml_comment.content)
      end

      def self.build_moxml_pi_node(moxml_pi)
        Nodes::ProcessingInstructionNode.new(
          target: moxml_pi.target,
          data: moxml_pi.data,
        )
      end
    end
  end
end
