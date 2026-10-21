# frozen_string_literal: true

module Canon
  module Xml
    # Canonical attribute ordering: every element's attributes are
    # re-attached in lexicographic name order. Both canonical lanes
    # consume this — the HTML formatter base and the XML pretty
    # printer — so attribute order is invariant across formats and
    # across input orderings (the equivalence-respect property,
    # TODO.sota/03).
    module AttributeSorter
      module_function

      def sort!(doc)
        walk_elements(doc.root) do |element|
          attrs = element.attributes
          next if attrs.empty?

          names = attrs.map(&:name)
          # Already-sorted is the common case — removing and re-adding
          # every attribute is expensive, so check first.
          next if names.each_cons(2).all? { |a, b| (a <=> b) <= 0 }

          sorted_attrs = attrs.sort_by(&:name)
          names.each { |name| element.remove_attribute(name) }
          sorted_attrs.each { |attr| element[attr.name] = attr.value }
        end
        doc
      end

      def walk_elements(node, &block)
        return unless node.is_a?(Moxml::Element)

        yield(node)
        node.children.to_a.each { |child| walk_elements(child, &block) }
      end
    end
  end
end
