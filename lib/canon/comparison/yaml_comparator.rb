# frozen_string_literal: true

require "yaml"
require_relative "json_comparator"

module Canon
  module Comparison
    # YAML comparison class
    # Handles comparison of YAML objects with various options
    class YamlComparator
      # Default comparison options for YAML
      DEFAULT_OPTS = {
        ignore_attr_order: true,
        verbose: false,
      }.freeze

      class << self
        # Compare two YAML objects for equivalence
        #
        # @param yaml1 [String, Hash, Array] First YAML
        # @param yaml2 [String, Hash, Array] Second YAML
        # @param opts [Hash] Comparison options
        # @return [Boolean, Array] true if equivalent, or array of diffs if
        #   verbose
        def equivalent?(yaml1, yaml2, opts = {})
          opts = DEFAULT_OPTS.merge(opts)

          # Parse YAML if strings
          obj1 = parse_yaml(yaml1)
          obj2 = parse_yaml(yaml2)

          differences = []
          result = JsonComparator.send(:compare_ruby_objects, obj1, obj2, opts,
                                        differences, "")

          if opts[:verbose]
            differences
          else
            result == Comparison::EQUIVALENT
          end
        end

        private

        # Parse YAML from string or return as-is
        def parse_yaml(obj)
          return obj unless obj.is_a?(String)

          YAML.safe_load(obj)
        end
      end
    end
  end
end
