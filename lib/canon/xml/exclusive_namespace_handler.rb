# frozen_string_literal: true

module Canon
  module Xml
    # Exclusive XML Canonicalization namespace law (W3C REC
    # xml-exc-c14n-20080702). Unlike C14N 1.1's render-all-in-scope
    # namespace axis, the exclusive law renders only namespaces that
    # are:
    #
    #   1. VISIBLY UTILIZED — the element's own prefix, or the prefix
    #      of an in-node-set attribute of the element; or
    #   2. IN THE InclusiveNamespaces PrefixList — the transform
    #      parameter that re-imports ancestor context.
    #
    # and then only when no rendered ancestor already carries the
    # same prefix=uri binding (the ancestor-dedup law C14N shares).
    # `#default` in the prefix list imports the default namespace.
    class ExclusiveNamespaceHandler < NamespaceHandler
      # @param encoder [CharacterEncoder]
      # @param inclusive_ns_prefixes [Array<String>] the
      #        InclusiveNamespaces PrefixList tokens (`#default`,
      #        bare prefixes; a trailing ':' on a token is spelling)
      def initialize(encoder, inclusive_ns_prefixes = [])
        super(encoder)
        @inclusive = inclusive_ns_prefixes.map { |p| p.to_s.chomp(":") }
        @inclusive_default = @inclusive.delete("#default")
      end

      private

      # The exclusive rendering set: visibly utilized ∪ inclusive
      # list, intersected with the element's in-scope namespace nodes.
      def renderable_namespaces(element)
        utilized = visibly_utilized_prefixes(element)
        element.namespace_nodes.sort_by(&:local_name).select do |ns|
          next false unless ns.in_node_set?

          if ns.default_namespace?
            @inclusive_default
          else
            utilized.include?(ns.prefix) || @inclusive.include?(ns.prefix)
          end
        end
      end

      # The element's own prefix plus the prefixes of its in-node-set
      # attributes (xml:* excluded — the XML namespace never renders).
      def visibly_utilized_prefixes(element)
        prefixes = []
        prefixes << element.prefix if element.prefix && !element.prefix.empty?
        element.attribute_nodes.each do |attr|
          next unless attr.in_node_set?
          next if attr.xml_base?
          next if attr.name == "xml:base"

          p = attr.prefix.to_s
          prefixes << p unless p.empty? || p == "xmlns"
        end
        prefixes.uniq
      end

      # The exclusive law replaces C14N's render-all selection.
      # (the `ns` param name is the file's shared vocabulary)
      def should_skip_namespace?(ns, elem, parent_element) # rubocop:disable Naming/MethodParameterName
        return true if ns.xml_namespace?

        namespace_declared_by_ancestor?(ns, elem, parent_element)
      end

      # The empty-default emission follows the inclusive list: only
      # when #default is imported and the in-scope default is
      # non-empty does xmlns="" re-appear.
      def should_emit_empty_default_namespace?(_element, namespaces,
                                               parent_element)
        return false unless @inclusive_default
        return false if namespaces.first&.default_namespace?
        return false unless parent_element

        parent_default_ns = parent_element.namespace_nodes.find do |ns|
          ns.default_namespace? && ns.in_node_set?
        end

        parent_default_ns && !parent_default_ns.uri.empty?
      end
    end
  end
end
