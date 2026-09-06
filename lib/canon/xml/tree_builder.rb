# frozen_string_literal: true

module Canon
  module Xml
    # The one place canon tree nodes are constructed from parsed XML.
    #
    # Owns construction semantics: namespace scopes, attribute
    # normalization, node kinds, and document-level ordering. Keep/strip
    # decisions come from WhitespacePolicy (one home for all three
    # policies); engine walks — the Nokogiri and moxml extractors in
    # Xml::DataModel, the HTML walk in Html::DataModel — only map their
    # engine's shapes onto this interface.
    #
    # Attribute normalization: duplicate (name, namespace) pairs are
    # invalid XML; engines expose them differently (libxml2 lists
    # repeats, libleptris deduplicates), so the builder resolves them
    # once — first occurrence wins.
    class TreeBuilder
      # Stateless module: one shared instance serves every feed.
      DEFAULT = new

      NO_ATTRIBUTES = [].freeze
      XML_NAMESPACE_PREFIX = "xml"
      XML_NAMESPACE_URI = "http://www.w3.org/XML/1998/namespace"

      # Repetitive short strings — element/attribute names, prefixes,
      # namespace URIs — are interned so one frozen instance is shared
      # across every tree canon builds: a thousand `<p>` elements hold
      # one "p". Values (text content, attribute values) are unique and
      # are never interned. Bounded; cleared when full.
      INTERN_LIMIT = 8192

      def intern(string)
        return string if string.nil?

        cache = (@string_intern_cache ||= {})
        cache.clear if cache.size >= INTERN_LIMIT
        cache.fetch(string) { cache[string] = string.freeze }
      end

      # In-scope namespace bindings: the element's own declarations
      # shadow inherited ones; xml is prebound at the base. Declaration
      # pairs are [prefix-or-nil, uri]; nil and "" both mean the default
      # namespace. Elements with no declarations return the inherited
      # scope unchanged — most elements — so equal scopes share one
      # object (and one namespace-node array, see attach). The xml
      # binding is materialized at the root even for undeclaring
      # elements: it is in scope on every element per the XPath data
      # model (and the SAX feed's initial stack carries it too).
      def merge_namespace_scope(inherited, declaration_pairs)
        return inherited if declaration_pairs.empty? && inherited

        scope = inherited ? inherited.dup : { XML_NAMESPACE_PREFIX => XML_NAMESPACE_URI }
        declaration_pairs.each do |prefix, uri|
          scope[prefix || ""] = uri
        end
        scope.freeze
      end

      # Attach an in-scope scope to an element as namespace nodes. The
      # node array is cached per scope object: elements that introduced
      # no declarations share their parent's array instead of
      # re-materializing one NamespaceNode per prefix per element.
      # NamespaceNode#parent is never read, so shared nodes carry the
      # first creator as parent by convention. The cache is identity
      # keyed and bounded — stale scopes of dead trees cost a few
      # hundred bytes until the next clear.
      def attach_namespace_scope(element, scope)
        cache = (@namespace_node_cache ||= {}.compare_by_identity)
        cache.clear if cache.size >= 4096
        nodes = cache[scope]
        if nodes.nil?
          nodes = scope.map do |prefix, uri|
            Nodes::NamespaceNode.new(prefix: intern(prefix), uri: intern(uri))
          end.freeze
          cache[scope] = nodes
        end
        element.namespace_nodes = nodes
      end

      # Build an element. `attributes` is a FLAT stride-4 array —
      # [name, value, namespace_uri, prefix, name, value, ...] — so the
      # moxml records feed hands its reused buffer straight through
      # (read synchronously below) and the tree feeds build one flat
      # array instead of one sub-array per attribute. `namespace_scope`
      # is a merged scope (or nil for no namespace nodes).
      def element(name:, prefix: nil, namespace_uri: nil,
                  attributes: NO_ATTRIBUTES, namespace_scope: nil)
        element = Nodes::ElementNode.new(
          name: intern(name),
          namespace_uri: intern(namespace_uri),
          prefix: intern(prefix),
        )
        attach_namespace_scope(element, namespace_scope) if namespace_scope

        # Duplicate (name, namespace) pairs are invalid XML — first
        # occurrence wins. Flat index arithmetic keeps the scan
        # allocation-free.
        base = 0
        limit = attributes.size
        while base < limit
          attr_name = attributes[base]
          attr_namespace_uri = attributes[base + 2]
          duplicate = false
          prior = 0
          while prior < base
            if attributes[prior] == attr_name &&
                attributes[prior + 2] == attr_namespace_uri
              duplicate = true
              break
            end
            prior += 4
          end

          unless duplicate
            element.add_attribute(Nodes::AttributeNode.new(
                                    name: intern(attr_name),
                                    value: attributes[base + 1],
                                    namespace_uri: intern(attr_namespace_uri),
                                    prefix: intern(attributes[base + 3]),
                                  ))
          end
          base += 4
        end

        element
      end

      # Build a text node; `keep` comes from WhitespacePolicy (the
      # caller knows the policy and parent context).
      def text(content, keep:, original: content)
        return nil unless keep

        Nodes::TextNode.new(value: content, original: original)
      end

      def comment(content)
        Nodes::CommentNode.new(value: content)
      end

      def processing_instruction(target, data)
        Nodes::ProcessingInstructionNode.new(target: target, data: data)
      end

      # Attach document-level children (prolog/epilog PIs, comments,
      # document-level text) to the canon root, in document order,
      # skipping the document element and the given types. Yields each
      # child to the caller's converter; nil results are dropped.
      def add_document_children(root, children, document_element,
                                skip_types = [])
        children.each do |child|
          next if child.equal?(document_element)
          next if skip_types.any? { |type| child.is_a?(type) }

          node = yield child
          root.add_child(node) if node
        end
      end
    end
  end
end
