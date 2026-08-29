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
      # namespace.
      def merge_namespace_scope(inherited, declaration_pairs)
        scope = inherited ? inherited.dup : { XML_NAMESPACE_PREFIX => XML_NAMESPACE_URI }
        declaration_pairs.each do |prefix, uri|
          scope[prefix || ""] = uri
        end
        scope
      end

      # Attach an in-scope scope to an element as namespace nodes.
      def attach_namespace_scope(element, scope)
        scope.each do |prefix, uri|
          element.add_namespace(Nodes::NamespaceNode.new(
                                  prefix: prefix,
                                  uri: uri,
                                ))
        end
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

        seen = {}
        attributes.each do |attr_name, value, attr_namespace_uri, attr_prefix|
          key = [attr_name, attr_namespace_uri]
          next if seen.key?(key)

          seen[key] = true
          element.add_attribute(Nodes::AttributeNode.new(
                                  name: attr_name,
                                  value: value,
                                  namespace_uri: attr_namespace_uri,
                                  prefix: attr_prefix,
                                ))
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
