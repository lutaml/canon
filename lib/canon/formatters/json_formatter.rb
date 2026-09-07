# frozen_string_literal: true

require "json"

module Canon
  module Formatters
    # JSON formatter for canonicalization
    class JsonFormatter
      def self.format(json)
        parsed = parse(json)
        JSON.pretty_generate(sort_json_keys(parsed))
      end

      def self.parse(json)
        # Validate before parsing
        Canon::Validators::JsonValidator.validate!(json)
        # Return as-is if already parsed
        return json if json.is_a?(Hash) || json.is_a?(Array)

        Canon::JsonParsing.parse(json)
      end

      def self.sort_json_keys(obj)
        case obj
        when Hash
          # Single pass: sorted keys once, one rebuilt hash. The
          # previous form (transform_values + sort.to_h) rebuilt every
          # container twice per canonicalization.
          sorted = {}
          obj.keys.sort.each { |key| sorted[key] = sort_json_keys(obj[key]) }
          sorted
        when Array
          obj.map { |item| sort_json_keys(item) }
        else
          obj
        end
      end
    end
  end
end
