# frozen_string_literal: true

module Canon
  module Html
    # Builds XPath data model from HTML
    # HTML-specific parsing with lowercase element/attribute names,
    # whitespace-sensitive element handling, and fragment parsing
    class DataModel < Canon::DataModel
      # Build XPath data model from HTML string
      #
      # The engine lane: moxml Context#parse_html_fragment (WHATWG
      # fragment parsing) → Canon tree. The +version:+ parameter is
      # accepted for API compatibility — the engine serves every input
      # through one WHATWG parse (the #118 html4/html5 unification).
      # Full documents keep their head content at the fragment top
      # level (the in-body rules ignore the html/body start tags but
      # preserve every other node); the former Nokogiri body-extraction
      # dropped head content entirely.
      #
      # @param html_string [String] HTML content to parse
      # @param version [Symbol] accepted for compatibility; unused
      # @return [Canon::Xml::Nodes::RootNode] Root of the data model tree
      # rubocop:disable-next Lint/UnusedMethodArgument -- API compatibility
      def self.from_html(html_string, version: :html4)
        engine_fragment(html_string)
      end

      # Parse an HTML string through the engine's WHATWG fragment
      # parsing and build a Canon tree from the fragment children.
      # Whitespace text nodes are preserved unconditionally — HTML
      # whitespace significance is the comparison profile's decision
      # (#112/#137), unlike the XML DOM lane's parse-time policy.
      # Top-level element children convert through the
      # materialize-records fast path; the wrapper walk serves the
      # rare non-element top-level nodes (text, comments).
      def self.engine_fragment(html)
        frag = Canon::XmlParsing.moxml_context.parse_html_fragment(html)
        root = Canon::Xml::Nodes::RootNode.new
        frag.children.each do |child|
          node =
            if child.is_a?(Moxml::Element)
              Canon::Xml::DataModel.build_moxml_subtree_from_records(
                child, preserve_whitespace: true
              )
            else
              Canon::Xml::DataModel.walk_moxml(child, preserve_whitespace: true)
            end
          root.add_child(node) if node
        end
        root
      end

      # Deterministic single-line engine formatting for the :format
      # string preprocessor — parse + re-serialize as a pure function
      # of the parsed tree.
      def self.engine_html_format(html)
        Canon::XmlParsing.moxml_context.parse_html(html).to_html
      end

      # Alias for compatibility
      def self.parse(html_string, version: :html4)
        from_html(html_string, version: version)
      end

      # Serialize HTML node to string
      def self.serialize(node)
        # HTML nodes use the same serialization as XML
        # Delegate to XML serialization implementation
        Canon::Xml::DataModel.serialize(node)
      end

      # Build XPath data model from a Nokogiri HTML document or
      # fragment — a TreeBuilder walk like the XML extractors, with the
      # HTML whitespace policy and xmlns-free attributes.
      def self.build_from_nokogiri(nokogiri_doc)
        builder = Canon::Xml::TreeBuilder::DEFAULT
        root = Canon::Xml::Nodes::RootNode.new
        skip_types = defined?(Nokogiri) ? [Nokogiri::XML::DTD] : []

        if nokogiri_doc.is_a?(Nokogiri::XML::Document) && nokogiri_doc.root
          root.add_child(walk(builder, nokogiri_doc.root))
          builder.add_document_children(root, nokogiri_doc.children,
                                        nokogiri_doc.root, skip_types) do |child|
            walk(builder, child)
          end
        else
          builder.add_document_children(root, nokogiri_doc.children,
                                        nil, skip_types) do |child|
            walk(builder, child)
          end
        end

        root
      end

      def self.walk(builder, node, inherited_namespaces: nil)
        case node
        when Nokogiri::XML::Element
          scope = builder.merge_namespace_scope(
            inherited_namespaces,
            node.namespace_definitions.map { |ns| [ns.prefix, ns.href] },
          )
          # HTML attributes are namespace-free; xmlns declarations are
          # not reported as attributes. Flat stride-4 array
          # (TreeBuilder#element contract).
          flat_attributes = []
          node.attribute_nodes.each do |attr|
            next if attr.name.start_with?("xmlns")

            flat_attributes << attr.name << attr.value << nil << nil
          end
          element = builder.element(
            name: node.name,
            prefix: node.namespace&.prefix,
            namespace_uri: node.namespace&.href,
            attributes: flat_attributes,
            namespace_scope: scope,
          )
          node.children.each do |child|
            built = walk(builder, child, inherited_namespaces: scope)
            element.add_child(built) if built
          end
          element
        when Nokogiri::XML::Text
          builder.text(
            node.content,
            keep: Canon::Xml::WhitespacePolicy.keep_html_text?(
              node.content,
              parent_name: node.parent.is_a?(Nokogiri::XML::Element) ? node.parent.name : nil,
              text_node: node,
            ),
          )
        when Nokogiri::XML::Comment
          builder.comment(node.content)
        when Nokogiri::XML::ProcessingInstruction
          builder.processing_instruction(node.name, node.content)
        end
      end

      class << self
        private :build_from_nokogiri, :walk
      end
    end
  end
end
