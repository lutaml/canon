# frozen_string_literal: true

require "yaml"

module Canon
  module Formatters
    # YAML formatter for canonicalization
    class YamlFormatter
      def self.format(yaml)
        parsed = parse(yaml)
        sort_yaml_keys(parsed).to_yaml
      end

      def self.parse(yaml)
        # Validate before parsing
        Canon::Validators::YamlValidator.validate!(yaml)
        # Return as-is if already parsed
        return yaml if yaml.is_a?(Hash) || yaml.is_a?(Array)

        Canon::YamlParsing.safe_load(yaml)
      end

      def self.sort_yaml_keys(obj)
        case obj
        when Hash
          # Single pass: sorted keys once, one rebuilt hash (the
          # transform_values + sort.to_h form rebuilt every container
          # twice).
          sorted = {}
          obj.keys.sort.each { |key| sorted[key] = sort_yaml_keys(obj[key]) }
          sorted
        when Array
          obj.map { |item| sort_yaml_keys(item) }
        else
          obj
        end
      end
    end
  end
end
