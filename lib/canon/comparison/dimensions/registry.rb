# frozen_string_literal: true

require_relative "base_dimension"
require_relative "text_content_dimension"
require_relative "comments_dimension"
require_relative "attribute_values_dimension"
require_relative "attribute_presence_dimension"
require_relative "attribute_order_dimension"
require_relative "element_position_dimension"
require_relative "structural_whitespace_dimension"

module Canon
  module Comparison
    module Dimensions
      # Registry for comparison dimensions
      #
      # Provides a central access point for all dimension classes
      # and maps dimension symbols to their implementations.
      module Registry
        # Dimension class mappings
        DIMENSION_CLASSES = {
          text_content: TextContentDimension,
          comments: CommentsDimension,
          attribute_values: AttributeValuesDimension,
          attribute_presence: AttributePresenceDimension,
          attribute_order: AttributeOrderDimension,
          element_position: ElementPositionDimension,
          structural_whitespace: StructuralWhitespaceDimension,
        }.freeze

        # Get a dimension instance by name
        #
        # @param dimension_name [Symbol] Dimension name
        # @return [BaseDimension] Dimension instance
        # @raise [Canon::Error] if dimension is unknown
        def self.get(dimension_name)
          dimension_class = DIMENSION_CLASSES[dimension_name]

          unless dimension_class
            raise Canon::Error,
                  "Unknown dimension: #{dimension_name}. " \
                  "Valid dimensions: #{DIMENSION_CLASSES.keys.join(', ')}"
          end

          dimension_class.new
        end

        # Get all available dimension names
        #
        # @return [Array<Symbol>] Available dimension names
        def self.available_dimensions
          DIMENSION_CLASSES.keys
        end

        # Check if a dimension is available
        #
        # @param dimension_name [Symbol] Dimension name
        # @return [Boolean] true if dimension is available
        def self.dimension_exists?(dimension_name)
          DIMENSION_CLASSES.key?(dimension_name)
        end

        # Compare two nodes for a specific dimension
        #
        # @param dimension_name [Symbol] Dimension name
        # @param node1 [Object] First node
        # @param node2 [Object] Second node
        # @param behavior [Symbol] Comparison behavior
        # @return [Boolean] true if nodes match for this dimension
        def self.compare(dimension_name, node1, node2, behavior)
          dimension = get(dimension_name)
          dimension.equivalent?(node1, node2, behavior)
        end
      end
    end
  end
end
