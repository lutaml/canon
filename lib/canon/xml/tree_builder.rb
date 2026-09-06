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
            Nodes::NamespaceNode.new(prefix: prefix, uri: uri)
          end.freeze
          cache[scope] = nodes
        end
        element.namespace_nodes = nodes
      end

      # Build an element. `attributes` are [name, value, namespace_uri,
      # prefix] pairs; `namespace_scope` is a merged scope (or nil for
      # no namespace nodes).
      def element(name:, prefix: nil, namespace_uri: nil,
                  attributes: NO_ATTRIBUTES, namespace_scope: nil)
        element = Nodes::ElementNode.new(
          name: name,
          namespace_uri: namespace_uri,
          prefix: prefix,
        )
        attach_namespace_scope(element, namespace_scope) if namespace_scope

        # Duplicate (name, namespace) pairs are invalid XML — first
        # occurrence wins. Index arithmetic instead of subarray slices:
        # the scan stays allocation-free on the hot paths.
        index = 0
        while index < attributes.size
          pair = attributes[index]
          attr_name = pair[0]
          attr_namespace_uri = pair[2]
          duplicate = false
          prior = 0
          while prior < index
            candidate = attributes[prior]
            if candidate[0] == attr_name && candidate[2] == attr_namespace_uri
              duplicate = true
              break
            end
            prior += 1
          end

          unless duplicate
            element.add_attribute(Nodes::AttributeNode.new(
                                    name: attr_name,
                                    value: pair[1],
                                    namespace_uri: attr_namespace_uri,
                                    prefix: pair[3],
                                  ))
          end
          index += 1
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
