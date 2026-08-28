# frozen_string_literal: true

module Canon
  # Backend-agnostic XML parsing, serialization, and type dispatch.
  #
  # Responsibilities (MECE):
  # - Engine actions: `parse` selects the XML engine chosen by
  #   Canon::XmlBackend (raw Nokogiri or moxml with its resolved adapter —
  #   leptris when installed, nokogiri otherwise).
  # - Node type dispatch: type queries and traversal answer for ANY
  #   recognized node (Nokogiri or moxml) regardless of the active engine —
  #   callers may hand us nodes from either library (user input, format
  #   detection). Dispatch is by node type, never by backend.
  #
  # `defined?(Nokogiri)` guards keep Nokogiri constants unresolved under
  # Opal (no NameError at runtime).
  #
  # OCP: adding a new engine means extending Canon::XmlBackend detection
  # plus the node-type union here; all comparator/formatter code stays
  # untouched because it goes through this module.
  module XmlParsing
    class << self
      def moxml_context
        # Opal needs the explicit rexml adapter: stock oga requires its
        # C extension there. CRuby defers to moxml's preferred adapter
        # (leptris when installed and capable, nokogiri otherwise).
        @moxml_context ||= Moxml.new(RUBY_ENGINE == "opal" ? :rexml : nil)
      end

      # The adapter moxml resolved on this runtime. This is the single
      # source of truth for engine capability: moxml owns the preference
      # order, canon never probes gems itself.
      def moxml_adapter_name
        moxml_context.config.adapter_name
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
          doc = moxml_context.parse("<__frag__>#{xml_string}</__frag__>", readonly: true)
          doc.root.children.to_a
        end
      end

      # --- Serialization ---

      def serialize(node)
        if defined?(Nokogiri) && node.is_a?(Nokogiri::XML::Document)
          node.to_xml(encoding: "UTF-8")
        else
          node.to_xml
        end
      end

      # --- Type checks (any recognized engine node) ---

      def document?(obj)
        return true if defined?(Nokogiri) && obj.is_a?(Nokogiri::XML::Document)

        obj.is_a?(Moxml::Document)
      end

      def xml_node?(obj)
        return true if defined?(Nokogiri) && obj.is_a?(Nokogiri::XML::Node)

        obj.is_a?(Moxml::Node)
      end

      def element?(node)
        return true if defined?(Nokogiri) && node.is_a?(Nokogiri::XML::Element)

        node.is_a?(Moxml::Element)
      end

      def text_node?(node)
        return true if defined?(Nokogiri) && node.is_a?(Nokogiri::XML::Text)

        node.is_a?(Moxml::Text)
      end

      def comment?(node)
        return true if defined?(Nokogiri) && node.is_a?(Nokogiri::XML::Comment)

        node.is_a?(Moxml::Comment)
      end

      def cdata?(node)
        return true if defined?(Nokogiri) && node.is_a?(Nokogiri::XML::CDATA)

        node.is_a?(Moxml::Cdata)
      end

      def processing_instruction?(node)
        return true if defined?(Nokogiri) && node.is_a?(Nokogiri::XML::ProcessingInstruction)

        node.is_a?(Moxml::ProcessingInstruction)
      end

      def document_fragment?(obj)
        defined?(Nokogiri) && obj.is_a?(Nokogiri::XML::DocumentFragment)
      end

      def dtd?(node)
        defined?(Nokogiri) && node.is_a?(Nokogiri::XML::DTD)
      end

      # --- Node traversal ---

      def children(node)
        if defined?(Nokogiri) && node.is_a?(Nokogiri::XML::Node)
          node.children.to_a
        elsif node.is_a?(Moxml::Node)
          node.children.to_a
        else
          []
        end
      end

      def name(node)
        if defined?(Nokogiri) && node.is_a?(Nokogiri::XML::Node)
          node.name
        elsif node.is_a?(Moxml::Node)
          node.name
        end
      end

      def text_content(node)
        if defined?(Nokogiri) && node.is_a?(Nokogiri::XML::Node)
          node.content
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
        if defined?(Nokogiri) && node.is_a?(Nokogiri::XML::Element)
          node.attributes.values
        elsif node.is_a?(Moxml::Element)
          node.attributes
        else
          []
        end
      end

      def attribute_value(node, attr_name)
        if defined?(Nokogiri) && node.is_a?(Nokogiri::XML::Element)
          node[attr_name.to_s]
        elsif node.is_a?(Moxml::Element)
          node[attr_name.to_s]
        end
      end

      def namespace_definitions(node)
        if defined?(Nokogiri) && node.is_a?(Nokogiri::XML::Element)
          node.namespace_definitions
        elsif node.is_a?(Moxml::Element)
          node.namespace_definitions
        else
          []
        end
      end

      def parent(node)
        return nil unless xml_node?(node)
        # Document nodes have no parent
        return nil if document?(node)

        node.parent
      end

      def namespace_uri(node)
        if defined?(Nokogiri) && node.is_a?(Nokogiri::XML::Element)
          node.namespace&.href
        elsif node.is_a?(Moxml::Element)
          node.namespace_uri
        end
      end

      # Returns a symbol for all engines (:element, :text, :comment, etc.)
      # or nil for unrecognised nodes.
      def node_type(node)
        if defined?(Nokogiri) && node.is_a?(Nokogiri::XML::Node)
          nokogiri_node_type(node)
        elsif node.is_a?(Moxml::Node)
          moxml_node_type(node)
        end
      end

      private

      # --- Nokogiri engine ---

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
        nokogiri_type_map[node.node_type]
      end

      def nokogiri_parse(xml_string, options)
        doc = Nokogiri::XML.parse(xml_string)
        doc = doc.remove_namespaces! if options[:remove_namespaces]
        doc
      end

      # --- Moxml engine ---

      # Readonly: canon only ever reads engine documents (conversion,
      # serialization) — leptris memoizes reads on readonly documents,
      # and mutation is refused loudly rather than silently corrupting.
      def moxml_parse(xml_string, _options)
        moxml_context.parse(xml_string, readonly: true)
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
