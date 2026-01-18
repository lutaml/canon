# frozen_string_literal: true

module Canon
  module Comparison
    # Public API for JSON parsing operations
    # Provides access to parsing functionality without using send()
    class JsonParser
      # Parse an object to Ruby object
      #
      # @param obj [String, Hash, Array] Object to parse
      # @return [Hash, Array] Parsed Ruby object
      def self.parse_json(obj)
        # Delegate to JsonComparator's private method via public API
        require_relative "json_comparator"
        JsonComparator.parse_json(obj)
      end
    end
  end
end
