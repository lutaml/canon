# frozen_string_literal: true

module Canon
  module Comparison
    module Dimensions
      # Immutable collection of dimensions for a specific format.
      #
      # Each format (XML, JSON, YAML) has its own DimensionSet listing the
      # comparison aspects relevant to that format.  Provides lookup by name,
      # enumeration, and existence checks.
      class DimensionSet
        attr_reader :format

        # @param format [Symbol] Format identifier (e.g., :xml, :json, :yaml)
        # @param dimensions [Array<Dimension>] Dimensions for this format
        def initialize(format, dimensions)
          @format = format
          @dimensions = dimensions.to_h do |dim|
            [dim.name, dim]
          end.freeze
          freeze
        end

        # Lookup a dimension by name.
        #
        # @param name [Symbol]
        # @return [Dimension, nil]
        def [](name)
          @dimensions[name]
        end

        # All dimension names for this format, in definition order.
        #
        # @return [Array<Symbol>]
        def names
          @dimensions.keys
        end

        # Whether this format has a dimension with the given name.
        #
        # @param name [Symbol]
        # @return [Boolean]
        def dimension?(name)
          @dimensions.key?(name)
        end
      end
    end
  end
end
