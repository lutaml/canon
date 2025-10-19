# frozen_string_literal: true

require "yaml"
require_relative "json_comparator"
require_relative "match_options"

module Canon
  module Comparison
    # YAML comparison class
    # Handles comparison of YAML objects with various options
    class YamlComparator
      # Default comparison options for YAML
      DEFAULT_OPTS = {
        # Output options
        verbose: false,

        # Match system options
        match_profile: nil,
        match: nil,
        preprocessing: nil,
        global_profile: nil,
        global_options: nil,

        # Diff display options
        diff: nil,
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

          # Resolve match options with format-specific defaults
          match_opts = MatchOptions::Yaml.resolve(
            format: :yaml,
            match_profile: opts[:match_profile],
            match: opts[:match],
            preprocessing: opts[:preprocessing],
            global_profile: opts[:global_profile],
            global_options: opts[:global_options],
          )

          # Store resolved match options for use in comparison logic
          opts[:match_opts] = match_opts

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

          YAML.safe_load(obj, aliases: true)
        end
      end
    end
  end
end
