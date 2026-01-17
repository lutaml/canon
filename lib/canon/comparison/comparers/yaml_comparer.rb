# frozen_string_literal: true

require "yaml"
require_relative "structure_comparer"

module Canon
  module Comparison
    # YAML data structure comparison
    #
    # Provides YAML-specific comparison behavior, including:
    # - YAML type anchors and aliases
    # - YAML-specific scalar types
    # - Comment handling
    # - Extends JSON comparison with YAML features
    #
    # Inherits common comparison functionality from StructureComparer.
    class YamlComparer < StructureComparer
      class << self
        # Compare two YAML documents
        #
        # @param data1 [String, Hash, Array] First YAML data
        # @param data2 [String, Hash, Array] Second YAML data
        # @param opts [Hash] Comparison options
        # @return [Boolean, ComparisonResult] Result of comparison
        def compare(data1, data2, opts = {})
          # Delegate to the existing YamlComparator
          require_relative "../yaml_comparator"
          YamlComparator.equivalent?(data1, data2, opts)
        end

        # Parse YAML from string or return as-is
        #
        # @param data [String, Hash, Array] Data to parse
        # @return [Hash, Array, Object] Parsed data structure
        def parse_data(data)
          return data unless data.is_a?(String)

          YAML.safe_load(data, aliases: true)
        end

        # Serialize a data structure to YAML string
        #
        # @param data [Hash, Array, Object] Data to serialize
        # @return [String] Serialized YAML string
        def serialize_data(data)
          case data
          when String
            data
          when Hash, Array
            YAML.dump(data)
          else
            data.to_s
          end
        end
      end
    end
  end
end
