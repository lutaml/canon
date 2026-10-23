# frozen_string_literal: true

module Canon
  module Xml
    # Exclusive XML Canonicalization (W3C REC xml-exc-c14n-20080702),
    # the Ruby reference processor. Differs from C14N 1.1 only in the
    # namespace axis: namespaces render when VISIBLY UTILIZED (the
    # element's own prefix or an attribute's prefix) or named in the
    # InclusiveNamespaces PrefixList — see ExclusiveNamespaceHandler.
    #
    #     ExclusiveC14n.canonicalize(xml)
    #     ExclusiveC14n.canonicalize(xml, inclusive_ns_prefixes:
    #                                       ["#default", "ds"])
    #     ExclusiveC14n.canonicalize(xml, xpath: "(//. | //@*)
    #                                            [ancestor-or-self::x]")
    #
    # The leptris native exclusive lane rides this face once the
    # engine ships it (the canon acceptance protocol: byte-identity
    # through this reference first).
    class ExclusiveC14n
      # Canonicalize a document (or an XPath-selected subset)
      # @param xml [String] XML document as string
      # @param with_comments [Boolean] Include comments in canonical form
      # @param inclusive_ns_prefixes [Array<String>] InclusiveNamespaces
      #        PrefixList tokens (`#default`, bare prefixes)
      # @param xpath [String, nil] subset selection (C14N node-set
      #        semantics); nil canonicalizes the whole document
      # @return [String] Canonical form in UTF-8
      def self.canonicalize(xml, with_comments: false,
                            inclusive_ns_prefixes: [], xpath: nil)
        root_node = DataModel.from_xml(xml)

        if xpath
          if (idiom = c14n_selection_idiom(xpath))
            matched = select_ancestor_or_self(root_node, *idiom)
            NodeSetMarker.mark(root_node, matched, keep_root: false)
          else
            matched = XPathEngine.evaluate(root_node, xpath)
            NodeSetMarker.mark(root_node, matched)
          end
        end

        processor = Processor.new(
          with_comments: with_comments,
          namespace_handler: ExclusiveNamespaceHandler.new(
            CharacterEncoder.new, inclusive_ns_prefixes
          ),
          inherit_xml_attributes: false,
        )
        processor.process(root_node)
      end

      # The C14N selection idiom the suite drives:
      #   (//. | //@* | //namespace::*)[ancestor-or-self::pfx:name]
      # — every node in the subtrees rooted at pfx:name. Returns
      # [prefix, local_name], or nil for anything else.
      def self.c14n_selection_idiom(xpath)
        # The suite's .xpath files are XML documents wrapping the
        # expression (with prefix declarations and inline comments).
        # Extraction is index-based string surgery — the CodeQL
        # polynomial-redos query flags the gsub-chain form.
        close_tag = xpath.rindex("</XPath>")
        text = close_tag ? xpath[0...close_tag] : xpath.dup
        # drop the XML declaration and the <XPath> open tag: each
        # ends at the first '>' at/after its '<'
        if (decl = text.index("<"))
          gt = text.index(">", decl)
          if (xopen = text.index("<XPath", decl)) && (xopen < gt)
            gt = text.index(">", xopen)
          end
          text = text[(gt + 1)..] if gt
        end
        # strip <!-- --> comments by index (no regex backtracking)
        loop do
          open_c = text.index("<!--")
          break unless open_c

          close_c = text.index("-->", open_c + 4)
          text = close_c ? text[0...open_c] + text[(close_c + 3)..] : text[0...open_c]
        end
        text = text.squeeze(" ")
        m = text.match(%r{\(//\.\s*\|\s*//@\*\s*\|\s*//namespace::\*\)\s*\[\s*ancestor-or-self::([A-Za-z_][\w.-]*)(?::([\w.-]+))?\s*\]\s*\z})
        return nil unless m

        m[2] ? [m[1], m[2]] : [nil, m[1]]
      end

      # The subtree roots whose ancestor-or-self chain touches
      # prefix:name (resolved through the document's bindings), with
      # deeper matches subsumed by their topmost ancestor.
      def self.select_ancestor_or_self(root_node, prefix, local_name)
        target_uri = nil
        walk = lambda do |el|
          if el.respond_to?(:namespace_nodes)
            el.namespace_nodes.each do |ns|
              next if ns.default_namespace?

              if ns.prefix == prefix || (prefix.nil? && ns.prefix.nil?)
                target_uri = ns.uri
                break
              end
            end
          end
          break if target_uri

          el.children.each { |c| walk.call(c) if c.node_type == :element }
        end
        root_node.children.each { |c| walk.call(c) if c.node_type == :element }

        tops = []
        collect = lambda do |el|
          hit = target_uri.nil? ? false : (el.namespace_uri == target_uri)
          hit ||= prefix.nil? && el.name == local_name
          if hit
            tops << el
          else
            el.children.each { |c| collect.call(c) if c.node_type == :element }
          end
        end
        root_node.children.each { |c| collect.call(c) if c.node_type == :element }
        tops
      end
    end
  end
end
