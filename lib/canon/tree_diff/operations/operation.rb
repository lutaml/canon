# frozen_string_literal: true

module Canon
  module TreeDiff
    module Operations
      # Base class for all tree diff operations
      #
      # Represents a high-level semantic operation detected from tree matching.
      # Each operation has a type, affected nodes, and metadata.
      #
      # @example
      #   operation = Operation.new(
      #     type: :insert,
      #     node: new_node,
      #     parent: parent_node,
      #     position: 2
      #   )
      #
      class Operation
        # Operation types based on XDiff and JATS-diff research
        TYPES = %i[
          insert
          delete
          update
          move
          merge
          split
          upgrade
          downgrade
        ].freeze

        attr_reader :type, :metadata

        # Initialize a new operation
        #
        # @param type [Symbol] Operation type (must be in TYPES)
        # @param metadata [Hash] Operation-specific metadata
        def initialize(type:, **metadata)
          unless TYPES.include?(type)
            raise ArgumentError, "Invalid operation type: #{type}"
          end

          @type = type
          @metadata = metadata
        end

        # Check if operation is a specific type
        #
        # @param type [Symbol] Type to check
        # @return [Boolean]
        def type?(type)
          @type == type
        end

        # Get a metadata value
        #
        # @param key [Symbol] Metadata key
        # @return [Object, nil] Metadata value
        def [](key)
          @metadata[key]
        end

        # Check if two operations are equal
        #
        # @param other [Operation] Other operation
        # @return [Boolean]
        def ==(other)
          return false unless other.is_a?(Operation)

          type == other.type && metadata == other.metadata
        end

        # String representation
        #
        # @return [String]
        def to_s
          "Operation(#{type})"
        end

        # Detailed string representation
        #
        # @return [String]
        def inspect
          metadata_str = @metadata.map { |k, v| "#{k}: #{v.inspect}" }.join(", ")
          "#<#{self.class.name} type=#{type} #{metadata_str}>"
        end
      end
    end
  end
end
