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
        when Nokogiri::XML::Text, Nokogiri::XML::CDATA
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
        # attribute_nodes, not the attributes hash: the hash is keyed by
        # local name and collapses e.g. attr / a:attr / b:attr into one
        # entry, losing namespaced attributes (W3C C14N ex 3.3).
        nokogiri_element.attribute_nodes.each do |attr|
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
        check_moxml_relative_namespace_uris(doc)
        result = build_from_moxml(doc, preserve_whitespace: preserve_whitespace)
        # Canon owns this document's full lifecycle: the canon tree holds
        # no engine references once built, so release the native tree now
        # instead of waiting for the GC finalizer (moxml#134; no-op on
        # GC-managed adapters).
        doc.free
        result
      end

      def self.check_moxml_relative_namespace_uris(node)
        case node
        when Moxml::Element
          node.namespace_definitions.each do |ns|
            href = ns.uri
            next if href.nil? || href.empty?
            if relative_uri?(href)
              raise Canon::Error,
                    "Relative namespace URI not allowed: #{href}"
            end
          end
          node.children.each { |child| check_moxml_relative_namespace_uris(child) }
        when Moxml::Document
          node.children.each { |child| check_moxml_relative_namespace_uris(child) }
        end
      end

      def self.build_from_moxml(moxml_doc, preserve_whitespace: false)
        root = Nodes::RootNode.new

        if moxml_doc.is_a?(Moxml::Document) && moxml_doc.root
          element = build_moxml_subtree_from_records(moxml_doc.root,
                                                     preserve_whitespace: preserve_whitespace)
          root.add_child(element) if element
          moxml_doc.children.each do |child|
            next if child.equal?(moxml_doc.root)
            next if child.is_a?(Moxml::Doctype)

            node = build_moxml_node(child,
                                    preserve_whitespace: preserve_whitespace)
            root.add_child(node) if node
          end
        else
          moxml_doc.children.each do |child|
            next if child.is_a?(Moxml::Doctype)

            node = build_moxml_node(child,
                                    preserve_whitespace: preserve_whitespace)
            root.add_child(node) if node
          end
        end

        root
      end

      # Document path: build the root subtree from materialize records —
      # one flattened record stream (moxml#132/#138) instead of a wrapper
      # walk, so conversion costs no Moxml::Node allocation per node.
      #
      # Records arrive post-order (children before parents): completed
      # nodes stack up with their depth, and an element record adopts
      # every completed node deeper than itself. Each element's OWN
      # namespace declarations ride an identity-keyed stash; afterwards
      # assign_moxml_namespace_scopes expands them to in-scope scopes
      # with the same first-wins/xml-prebound semantics as the Nokogiri
      # collector.
      def self.build_moxml_subtree_from_records(moxml_element,
preserve_whitespace: false)
        frames = []
        own_namespaces = {}.compare_by_identity

        moxml_element.materialize do |record|
          # The record contract is root-subtree-only since moxml 0.5.11
          # (moxml#140). Older 0.5.x releases — still allowed by canon's
          # gemspec floor — leaked epilog document-level records at depth
          # 0, which the document-children enumeration below also covers;
          # one integer compare per record keeps those working.
          next if record[:depth].zero? && record[:kind] != :element

          node = case record[:kind]
                 when :element
                   build_moxml_element_from_record(record, frames,
                                                   own_namespaces)
                 when :text, :cdata
                   build_moxml_text_from_record(record, preserve_whitespace)
                 when :comment
                   Nodes::CommentNode.new(value: record[:text])
                 when :processing_instruction
                   Nodes::ProcessingInstructionNode.new(
                     target: record[:qname],
                     data: record[:text] || "",
                   )
                 end

          frames.push([record[:depth], node]) if node
        end

        top = frames.last
        return nil unless top

        element = top[1]
        assign_moxml_namespace_scopes(element,
                                      { "xml" => "http://www.w3.org/XML/1998/namespace" },
                                      own_namespaces)
        element
      end

      def self.build_moxml_element_from_record(record, frames, own_namespaces)
        element = Nodes::ElementNode.new(
          name: record[:qname],
          namespace_uri: record[:namespace_uri],
          prefix: record[:prefix],
        )

        seen = {}
        record[:attributes].each do |name, value, namespace_uri, prefix|
          key = [name, namespace_uri]
          next if seen.key?(key)

          seen[key] = true
          element.add_attribute(Nodes::AttributeNode.new(
                                  name: name,
                                  value: value,
                                  namespace_uri: namespace_uri,
                                  prefix: prefix,
                                ))
        end

        # Adopt completed children (they stack in reverse: unshift
        # restores document order).
        children = []
        children.unshift(frames.pop[1]) while frames.any? && frames.last[0] > record[:depth]
        children.each { |child| element.add_child(child) }

        own_namespaces[element] = record[:namespaces]
        element
      end

      # Text records inside a document subtree always have an element
      # parent (only the document element sits at depth 0), so the
      # whitespace-only skip rule matches the wrapper path exactly.
      def self.build_moxml_text_from_record(record, preserve_whitespace)
        content = record[:text].to_s
        return nil if !preserve_whitespace && content.strip.empty?

        Nodes::TextNode.new(value: content, original: content)
      end

      # Expand each element's own declarations to in-scope bindings:
      # the element's declarations shadow inherited ones; xml is
      # prebound. Scope flows down the canon tree — no engine calls.
      def self.assign_moxml_namespace_scopes(element, inherited, own_namespaces)
        scope = inherited.dup
        own_namespaces[element].to_a.each do |prefix, uri|
          scope[prefix || ""] = uri
        end

        scope.each do |prefix, uri|
          element.add_namespace(Nodes::NamespaceNode.new(
                                  prefix: prefix,
                                  uri: uri,
                                ))
        end

        element.children.each do |child|
          assign_moxml_namespace_scopes(child, scope, own_namespaces) if child.is_a?(Nodes::ElementNode)
        end
      end

      def self.build_moxml_node(node, preserve_whitespace: false,
inherited_namespaces: nil)
        case node
        when Moxml::Element
          build_moxml_element_node(node,
                                   preserve_whitespace: preserve_whitespace,
                                   inherited_namespaces: inherited_namespaces)
        when Moxml::Text, Moxml::Cdata
          build_moxml_text_node(node, preserve_whitespace: preserve_whitespace)
        when Moxml::Comment
          build_moxml_comment_node(node)
        when Moxml::ProcessingInstruction
          build_moxml_pi_node(node)
        end
      end

      def self.build_moxml_element_node(moxml_element,
preserve_whitespace: false,
inherited_namespaces: nil)
        ns = moxml_element.namespace
        element = Nodes::ElementNode.new(
          name: moxml_element.name,
          namespace_uri: ns&.uri,
          prefix: ns&.prefix,
        )

        scope = moxml_namespace_scope(moxml_element, inherited_namespaces)
        scope.each do |prefix, uri|
          element.add_namespace(Nodes::NamespaceNode.new(
                                  prefix: prefix,
                                  uri: uri,
                                ))
        end

        build_moxml_attribute_nodes(moxml_element, element)

        moxml_element.children.each do |child|
          node = build_moxml_node(child,
                                  preserve_whitespace: preserve_whitespace,
                                  inherited_namespaces: scope)
          element.add_child(node) if node
        end

        element
      end

      # In-scope namespace bindings: the element's own declarations
      # shadow inherited ones, xml is prebound. The scope is passed down
      # the recursion so each element pays one declaration fetch instead
      # of an ancestor walk through the adapter layer (the Nokogiri
      # collector walks ancestors because those calls are cheap there).
      def self.moxml_namespace_scope(moxml_element, inherited)
        scope = inherited ? inherited.dup : { "xml" => "http://www.w3.org/XML/1998/namespace" }
        moxml_element.namespace_definitions.each do |decl|
          scope[decl.prefix || ""] = decl.uri
        end
        scope
      end

      def self.build_moxml_attribute_nodes(moxml_element, element)
        seen = {}
        moxml_element.attributes.each do |attr|
          # Duplicate attribute names are invalid XML; engines expose
          # them differently (libxml2 lists repeats, libleptris dedups
          # last-wins). Canon follows the Nokogiri presentation contract:
          # first occurrence wins, keyed by name + namespace.
          key = [attr.name, attr.namespace&.uri]
          next if seen.key?(key)

          seen[key] = true
          element.add_attribute(Nodes::AttributeNode.new(
                                  name: attr.name,
                                  value: attr.value,
                                  namespace_uri: attr.namespace&.uri,
                                  prefix: attr.namespace&.prefix,
                                ))
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
          data: moxml_pi.content,
        )
      end
    end
  end
end
