# frozen_string_literal: true

module Canon
  module Comparison
    # Dimension value objects for comparison aspects.
    #
    # Each format (XML/HTML, JSON, YAML) has a distinct set of dimensions —
    # specific aspects of a document that can be compared with different
    # behaviors (:strict, :normalize, :ignore).
    #
    # A Dimension knows its metadata (name, valid behaviors, normative
    # classification rule).  Comparison logic stays in the comparators where
    # it has full node context.
    #
    # DimensionSet groups dimensions per format.  Registry provides pre-built
    # sets with format lookup (html/html4/html5 all resolve to the XML set).
    module Dimensions
      autoload :Dimension, "canon/comparison/dimensions/dimension"
      autoload :DimensionSet, "canon/comparison/dimensions/dimension_set"
      autoload :Registry, "canon/comparison/dimensions/registry"
    end
  end
end
