# frozen_string_literal: true

require "nokogiri" unless RUBY_ENGINE == "opal"
require "set"

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

      # --- Engine extractors ---
      #
      # Traversal and engine mapping only. Each walk maps its engine's
      # shapes onto TreeBuilder's interface; all construction semantics
      # (namespace scopes, attribute normalization, whitespace policy,
      # node kinds, document ordering) live in TreeBuilder and
      # WhitespacePolicy — one dialect, three feeds.

      # -- Nokogiri walk: top-down, scope flows down the recursion --

      def self.build_from_nokogiri(nokogiri_doc, preserve_whitespace: false)
        root = Nodes::RootNode.new
        skip_types = defined?(Nokogiri) ? [Nokogiri::XML::DTD] : []

        if nokogiri_doc.is_a?(Nokogiri::XML::Document) && nokogiri_doc.root
          root.add_child(walk_nokogiri(nokogiri_doc.root,
                                       preserve_whitespace: preserve_whitespace))
          TreeBuilder::DEFAULT.add_document_children(root, nokogiri_doc.children,
                                                     nokogiri_doc.root, skip_types) do |child|
            walk_nokogiri(child, preserve_whitespace: preserve_whitespace)
          end
        else
          TreeBuilder::DEFAULT.add_document_children(root, nokogiri_doc.children,
                                                     nil, skip_types) do |child|
            walk_nokogiri(child, preserve_whitespace: preserve_whitespace)
          end
        end

        root
      end

      def self.walk_nokogiri(node, preserve_whitespace:,
inherited_namespaces: nil)
        case node
        when Nokogiri::XML::Element
          scope = TreeBuilder::DEFAULT.merge_namespace_scope(
            inherited_namespaces,
            node.namespace_definitions.map { |ns| [ns.prefix, ns.href] },
          )
          element = TreeBuilder::DEFAULT.element(
            name: node.name,
            prefix: node.namespace&.prefix,
            namespace_uri: node.namespace&.href,
            attributes: node.attribute_nodes.map do |attr|
              [attr.name, attr.value, attr.namespace&.href, attr.namespace&.prefix]
            end,
            namespace_scope: scope,
          )
          node.children.each do |child|
            built = walk_nokogiri(child,
                                  preserve_whitespace: preserve_whitespace,
                                  inherited_namespaces: scope)
            element.add_child(built) if built
          end
          element
        when Nokogiri::XML::Text, Nokogiri::XML::CDATA
          TreeBuilder::DEFAULT.text(node.content,
                                    keep: WhitespacePolicy.keep_dom_text?(
                                      node.content,
                                      preserve_whitespace: preserve_whitespace,
                                      element_parent: node.parent.is_a?(Nokogiri::XML::Element),
                                    ),
                                    original: node.to_xml)
        when Nokogiri::XML::Comment
          TreeBuilder::DEFAULT.comment(node.content)
        when Nokogiri::XML::ProcessingInstruction
          TreeBuilder::DEFAULT.processing_instruction(node.name, node.content)
        end
      end

      # -- moxml record stream: post-order frames adopt children --
      # One flattened record stream (moxml#132/#138) instead of a
      # wrapper walk, so document conversion costs no Moxml::Node
      # allocation per node. Own namespace declarations ride an
      # identity-keyed stash; assign_moxml_namespace_scopes expands
      # them to in-scope scopes afterwards (post-order arrival means
      # scopes cannot flow down during the stream).

      def self.from_moxml_xml(xml_string, preserve_whitespace:)
        # strict: false keeps the Nokogiri-engine contract — malformed
        # input yields a recovered document plus diagnostics instead of
        # an exception (moxml 0.5.15 defaults strict to true; issue
        # #147 rides recover errors on Document#parse_errors).
        doc = Canon::XmlParsing.moxml_context.parse(xml_string,
                                                    readonly: true,
                                                    strict: false)
        result = build_from_moxml(doc, preserve_whitespace: preserve_whitespace)
        result.parse_errors = doc.parse_errors if doc.parse_errors.any?
        # Canon owns this document's full lifecycle: the canon tree holds
        # no engine references once built, so release the native tree now
        # instead of waiting for the GC finalizer (moxml#134; no-op on
        # GC-managed adapters).
        doc.free
        result
      end

      def self.build_from_moxml(moxml_doc, preserve_whitespace: false)
        root = Nodes::RootNode.new
        skip_types = [Moxml::Doctype]

        if moxml_doc.is_a?(Moxml::Document) && moxml_doc.root
          element = build_moxml_subtree_from_records(moxml_doc.root,
                                                     preserve_whitespace: preserve_whitespace)
          root.add_child(element) if element
          TreeBuilder::DEFAULT.add_document_children(root, moxml_doc.children,
                                                     moxml_doc.root, skip_types) do |child|
            walk_moxml(child, preserve_whitespace: preserve_whitespace)
          end
        else
          TreeBuilder::DEFAULT.add_document_children(root, moxml_doc.children,
                                                     nil, skip_types) do |child|
            walk_moxml(child, preserve_whitespace: preserve_whitespace)
          end
        end

        root
      end

      def self.build_moxml_subtree_from_records(moxml_element,
preserve_whitespace: false)
        frames = []
        own_namespaces = {}.compare_by_identity

        # materialize_fields: the zero-allocation hot path (moxml#143).
        # Flat reused buffers — attributes stride 4, namespaces stride
        # 2 — valid only inside the block, so the element builder
        # copies them into pairs before returning.
        moxml_element.materialize_fields do |kind, qname, prefix, namespace_uri, namespaces, attributes, text, depth|
          # The record contract is root-subtree-only since moxml 0.5.11
          # (moxml#140). Older 0.5.x releases — still allowed by canon's
          # gemspec floor — leaked epilog document-level records at depth
          # 0, which the document-children enumeration also covers; one
          # integer compare per record keeps those working.
          next if depth.zero? && kind != :element

          # Relative-namespace validation rides the stream (the
          # namespaces buffer is the element's own declarations) — no
          # separate wrapper-tree walk per parse.
          if kind == :element
            i = 1
            while i < namespaces.size
              href = namespaces[i]
              if !href.nil? && !href.empty? && relative_uri?(href)
                raise Canon::Error,
                      "Relative namespace URI not allowed: #{href}"
              end
              i += 2
            end
          end

          node = case kind
                 when :element
                   build_moxml_element_from_fields(
                     qname, prefix, namespace_uri, namespaces, attributes,
                     depth, frames, own_namespaces
                   )
                 when :text, :cdata
                   content = text.to_s
                   TreeBuilder::DEFAULT.text(content,
                                             keep: WhitespacePolicy.keep_dom_text?(
                                               content, preserve_whitespace: preserve_whitespace
                                             ))
                 when :comment
                   TreeBuilder::DEFAULT.comment(text)
                 when :processing_instruction
                   TreeBuilder::DEFAULT.processing_instruction(qname, text || "")
                 end

          frames.push([depth, node]) if node
        end

        top = frames.last
        return nil unless top

        assign_moxml_namespace_scopes(top[1], nil, own_namespaces)
        top[1]
      end

      def self.build_moxml_element_from_fields(qname, prefix, namespace_uri,
                                               namespaces, attributes, depth,
                                               frames, own_namespaces)
        element = TreeBuilder::DEFAULT.element(
          name: qname,
          prefix: prefix,
          namespace_uri: namespace_uri,
          attributes: attributes.each_slice(4).to_a,
        )

        # Adopt completed children: they pop in reverse order; reversing
        # once is O(n) (unshift per child would be O(n^2) on wide trees).
        children = []
        children << frames.pop[1] while frames.any? && frames.last[0] > depth
        children.reverse_each { |child| element.add_child(child) }

        # Copy the declarations out of the reused buffer.
        own_namespaces[element] = namespaces.each_slice(2).to_a
        element
      end

      def self.assign_moxml_namespace_scopes(element, inherited, own_namespaces)
        scope = TreeBuilder::DEFAULT.merge_namespace_scope(inherited,
                                                           own_namespaces[element].to_a)
        TreeBuilder::DEFAULT.attach_namespace_scope(element, scope)

        element.children.each do |child|
          assign_moxml_namespace_scopes(child, scope, own_namespaces) if child.is_a?(Nodes::ElementNode)
        end
      end

      # -- moxml wrapper walk: fragments and user-supplied nodes --

      def self.walk_moxml(node, preserve_whitespace: false,
inherited_namespaces: nil)
        case node
        when Moxml::Element
          scope = TreeBuilder::DEFAULT.merge_namespace_scope(
            inherited_namespaces,
            node.namespace_definitions.map { |ns| [ns.prefix, ns.uri] },
          )
          element = TreeBuilder::DEFAULT.element(
            name: node.name,
            prefix: node.namespace&.prefix,
            namespace_uri: node.namespace&.uri,
            attributes: node.attributes.map do |attr|
              [attr.name, attr.value, attr.namespace&.uri, attr.namespace&.prefix]
            end,
            namespace_scope: scope,
          )
          node.children.each do |child|
            built = walk_moxml(child,
                               preserve_whitespace: preserve_whitespace,
                               inherited_namespaces: scope)
            element.add_child(built) if built
          end
          element
        when Moxml::Text, Moxml::Cdata
          TreeBuilder::DEFAULT.text(node.content,
                                    keep: WhitespacePolicy.keep_dom_text?(
                                      node.content,
                                      preserve_whitespace: preserve_whitespace,
                                      element_parent: node.parent.is_a?(Moxml::Element),
                                    ))
        when Moxml::Comment
          TreeBuilder::DEFAULT.comment(node.content)
        when Moxml::ProcessingInstruction
          TreeBuilder::DEFAULT.processing_instruction(node.target, node.content)
        end
      end
    end
  end
end
