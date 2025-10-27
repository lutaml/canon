# frozen_string_literal: true

require "yaml"
require_relative "../validators/yaml_validator"

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

        YAML.safe_load(yaml, permitted_classes: [Symbol, Date, Time])
      end

      def self.sort_yaml_keys(obj)
        case obj
        when Hash
          obj.transform_values { |v| sort_yaml_keys(v) }
            .sort.to_h
        when Array
          obj.map { |item| sort_yaml_keys(item) }
        else
          obj
        end
      end
    end
  end
end
