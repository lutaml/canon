# frozen_string_literal: true

module Canon
  # Backend-agnostic XML parsing, serialization, and type dispatch.
  #
  # Provides a unified API that delegates to the active backend
  # (Nokogiri or moxml/Oga). Uses backend-branching (`if XmlBackend.nokogiri?`)
  # rather than `case/when` with constant references — this ensures Nokogiri
  # constants are never resolved under Opal, preventing NameError at runtime.
  #
  # OCP: adding a new backend only requires updating this module.
  # DRY: all backend dispatch centralized here, not scattered across
  # comparator/formatter files.
  module XmlParsing
    class << self
      def moxml_context
        @moxml_context ||= Moxml.new(:oga)
      end

      # --- Parsing ---

      def parse(xml_string, options = {})
        if XmlBackend.nokogiri?
          nokogiri_parse(xml_string, options)
        else
          moxml_parse(xml_string, options)
        end
      end

      def parse_fragment(xml_string)
        if XmlBackend.nokogiri?
          Nokogiri::XML.fragment(xml_string).children.to_a
        else
          doc = moxml_context.parse("<__frag__>#{xml_string}</__frag__>")
          doc.root.children.to_a
        end
      end

      # --- Serialization ---

      def serialize(node)
        if XmlBackend.nokogiri?
          nokogiri_serialize(node)
        else
          moxml_serialize(node)
        end
      end

      # --- Type checks (backend-safe) ---
      #
      # Both Nokogiri and Moxml are loaded as dependencies. XmlBackend
      # determines which is used for *parsing*, but nodes from either
      # library may flow through comparison code (e.g. tests, format
      # detection). Under Nokogiri backend, both types are checked.

      def document?(obj)
        if XmlBackend.nokogiri?
          obj.is_a?(Nokogiri::XML::Document) || obj.is_a?(Moxml::Document)
        else
          obj.is_a?(Moxml::Document)
        end
      end

      def xml_node?(obj)
        if XmlBackend.nokogiri?
          obj.is_a?(Nokogiri::XML::Node) || obj.is_a?(Moxml::Node)
        else
          obj.is_a?(Moxml::Node)
        end
      end

      def element?(node)
        if XmlBackend.nokogiri?
          node.is_a?(Nokogiri::XML::Element) || node.is_a?(Moxml::Element)
        else
          node.is_a?(Moxml::Element)
        end
      end

      def text_node?(node)
        if XmlBackend.nokogiri?
          node.is_a?(Nokogiri::XML::Text) || node.is_a?(Moxml::Text)
        else
          node.is_a?(Moxml::Text)
        end
      end

      def comment?(node)
        if XmlBackend.nokogiri?
          node.is_a?(Nokogiri::XML::Comment) || node.is_a?(Moxml::Comment)
        else
          node.is_a?(Moxml::Comment)
        end
      end

      def cdata?(node)
        if XmlBackend.nokogiri?
          node.is_a?(Nokogiri::XML::CDATA) || node.is_a?(Moxml::Cdata)
        else
          node.is_a?(Moxml::Cdata)
        end
      end

      def processing_instruction?(node)
        if XmlBackend.nokogiri?
          node.is_a?(Nokogiri::XML::ProcessingInstruction) || node.is_a?(Moxml::ProcessingInstruction)
        else
          node.is_a?(Moxml::ProcessingInstruction)
        end
      end

      def document_fragment?(obj)
        if XmlBackend.nokogiri?
          obj.is_a?(Nokogiri::XML::DocumentFragment)
        else
          false
        end
      end

      def dtd?(node)
        if XmlBackend.nokogiri?
          node.is_a?(Nokogiri::XML::DTD)
        else
          false
        end
      end

      # --- Node traversal ---

      def children(node)
        if XmlBackend.nokogiri?
          node.is_a?(Nokogiri::XML::Node) ? node.children.to_a : []
        else
          node.is_a?(Moxml::Node) ? node.children.to_a : []
        end
      end

      def name(node)
        if XmlBackend.nokogiri?
          node.is_a?(Nokogiri::XML::Node) ? node.name : nil
        else
          node.is_a?(Moxml::Node) ? node.name : nil
        end
      end

      def text_content(node)
        if XmlBackend.nokogiri?
          node.is_a?(Nokogiri::XML::Node) ? node.content : node.to_s
        else
          case node
          when Moxml::Text, Moxml::Cdata, Moxml::Comment
            node.content.to_s
          when Moxml::Node
            node.text.to_s
          else
            node.to_s
          end
        end
      end

      def attributes(node)
        if XmlBackend.nokogiri?
          node.is_a?(Nokogiri::XML::Element) ? node.attributes.values : []
        else
          node.is_a?(Moxml::Element) ? node.attributes : []
        end
      end

      def attribute_value(node, attr_name)
        if XmlBackend.nokogiri?
          node.is_a?(Nokogiri::XML::Element) ? node[attr_name.to_s] : nil
        else
          node.is_a?(Moxml::Element) ? node[attr_name.to_s] : nil
        end
      end

      def namespace_definitions(node)
        if XmlBackend.nokogiri?
          node.is_a?(Nokogiri::XML::Element) ? node.namespace_definitions : []
        else
          node.is_a?(Moxml::Element) ? node.namespace_definitions : []
        end
      end

      def parent(node)
        return nil unless xml_node?(node)
        # Document nodes have no parent
        return nil if document?(node)

        node.parent
      end

      def namespace_uri(node)
        if XmlBackend.nokogiri?
          node.namespace&.href if node.is_a?(Nokogiri::XML::Element)
        elsif node.is_a?(Moxml::Element)
          node.namespace_uri
        end
      end

      # Returns a symbol for all backends (:element, :text, :comment, etc.)
      # or nil for unrecognised nodes.
      def node_type(node)
        if XmlBackend.nokogiri?
          nokogiri_node_type(node)
        else
          moxml_node_type(node)
        end
      end

      def canonicalize(node, options = {})
        if XmlBackend.nokogiri?
          node.canonicalize(options)
        else
          moxml_canonicalize(node, options)
        end
      end

      private

      # --- Nokogiri backend ---

      def nokogiri_type_map
        @nokogiri_type_map ||= {
          Nokogiri::XML::Node::ELEMENT_NODE => :element,
          Nokogiri::XML::Node::TEXT_NODE => :text,
          Nokogiri::XML::Node::CDATA_SECTION_NODE => :cdata,
          Nokogiri::XML::Node::COMMENT_NODE => :comment,
          Nokogiri::XML::Node::PI_NODE => :processing_instruction,
          Nokogiri::XML::Node::DOCUMENT_NODE => :document,
          Nokogiri::XML::Node::DOCUMENT_FRAG_NODE => :document_fragment,
          Nokogiri::XML::Node::DTD_NODE => :dtd,
          Nokogiri::XML::Node::ATTRIBUTE_NODE => :attribute,
        }.freeze
      end

      def nokogiri_node_type(node)
        return nil unless node.is_a?(Nokogiri::XML::Node)

        nokogiri_type_map[node.node_type]
      end

      def nokogiri_parse(xml_string, options)
        doc = Nokogiri::XML.parse(xml_string)
        doc = doc.remove_namespaces! if options[:remove_namespaces]
        doc
      end

      def nokogiri_serialize(node)
        if node.is_a?(Nokogiri::XML::Document)
          node.to_xml(encoding: "UTF-8")
        else
          node.to_xml
        end
      end

      # --- Moxml backend ---

      def moxml_parse(xml_string, _options)
        moxml_context.parse(xml_string)
      end

      def moxml_serialize(node)
        node.to_xml
      end

      def moxml_canonicalize(node, _options)
        node.to_xml
      end

      def moxml_node_type(node)
        return :element if node.element?
        return :text if node.text?
        return :comment if node.comment?
        return :cdata if node.cdata?
        return :document if node.document?
        return :processing_instruction if node.processing_instruction?

        nil
      end
    end
  end
end
