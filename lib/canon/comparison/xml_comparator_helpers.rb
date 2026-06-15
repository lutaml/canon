# frozen_string_literal: true

module Canon
  module Comparison
    # Helper classes used by {XmlComparator}. Children are autoloaded —
    # never `require_relative` them.
    module XmlComparatorHelpers
      autoload :AttributeComparator,
               "canon/comparison/xml_comparator/attribute_comparator"
      autoload :AttributeFilter,
               "canon/comparison/xml_comparator/attribute_filter"
      autoload :ChildComparison,
               "canon/comparison/xml_comparator/child_comparison"
      autoload :NamespaceComparator,
               "canon/comparison/xml_comparator/namespace_comparator"
      autoload :NodeParser, "canon/comparison/xml_comparator/node_parser"
      autoload :NodeTypeComparator,
               "canon/comparison/xml_comparator/node_type_comparator"
    end
  end
end
