# frozen_string_literal: true

require "json"
require_relative "structure_comparer"
require_relative "../json_parser"

module Canon
  module Comparison
    # JSON data structure comparison
    #
    # Provides JSON-specific comparison behavior, including:
    # - Strict key ordering (default) vs flexible ordering
    # - JSON-specific type handling
    # - JSON value normalization
    #
    # Inherits common comparison functionality from StructureComparer.
    class JsonComparer < StructureComparer
      class << self
        # Compare two JSON documents
        #
        # @param data1 [String, Hash, Array] First JSON data
        # @param data2 [String, Hash, Array] Second JSON data
        # @param opts [Hash] Comparison options
        # @return [Boolean, ComparisonResult] Result of comparison
        def compare(data1, data2, opts = {})
          # Delegate to the existing JsonComparator
          require_relative "../json_comparator"
          JsonComparator.equivalent?(data1, data2, opts)
        end

        # Parse JSON from string or return as-is
        #
        # @param data [String, Hash, Array] Data to parse
        # @return [Hash, Array, Object] Parsed data structure
        def parse_data(data)
          return data unless data.is_a?(String)

          JSON.parse(data)
        end

        # Serialize a data structure to JSON string
        #
        # @param data [Hash, Array, Object] Data to serialize
        # @return [String] Serialized JSON string
        def serialize_data(data)
          case data
          when String
            data
          when Hash, Array
            JSON.pretty_generate(data)
          else
            data.to_s
          end
        end
      end
    end
  end
end
