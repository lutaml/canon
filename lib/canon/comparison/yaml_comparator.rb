# frozen_string_literal: true

require "yaml"

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
        # Parse YAML from string or return as-is
        #
        # @param obj [String, Hash, Array] YAML string or parsed object
        # @return [Object] Parsed YAML object
        def parse(obj)
          parse_yaml(obj)
        end

        # Compare two YAML objects for equivalence
        #
        # @param yaml1 [String, Hash, Array] First YAML
        # @param yaml2 [String, Hash, Array] Second YAML
        # @param opts [Hash] Comparison options
        # @return [Boolean, ComparisonResult] true if equivalent, or ComparisonResult if verbose
        def equivalent?(yaml1, yaml2, opts = {})
          opts = DEFAULT_OPTS.merge(opts)

          # Resolve match options with format-specific defaults
          match_opts_hash = MatchOptions::Yaml.resolve(
            format: :yaml,
            match_profile: opts[:match_profile],
            match: opts[:match],
            preprocessing: opts[:preprocessing],
            global_profile: opts[:global_profile],
            global_options: opts[:global_options],
          )

          # Wrap in ResolvedMatchOptions for consistency with XML/HTML/JSON
          Canon::Comparison::ResolvedMatchOptions.new(
            match_opts_hash,
            format: :yaml,
          )

          # Store resolved match options for use in comparison logic
          opts[:match_opts] = match_opts_hash

          # Parse YAML if strings
          obj1 = parse_yaml(yaml1)
          obj2 = parse_yaml(yaml2)

          differences = []
          result = RubyObjectComparator.compare_objects(obj1, obj2, opts,
                                                        differences, "")

          if opts[:verbose]
            # Format YAML for display — deferred until first read
            preprocessed = lambda do
              [
                obj1.is_a?(String) ? obj1 : Canon::YamlParsing.dump(obj1),
                obj2.is_a?(String) ? obj2 : Canon::YamlParsing.dump(obj2),
              ]
            end

            ComparisonResult.new(
              differences: differences,
              preprocessed_strings: preprocessed,
              format: :yaml,
              match_options: match_opts_hash,
            )
          else
            result == Comparison::EQUIVALENT
          end
        end

        private

        # Parse YAML from string or return as-is
        def parse_yaml(obj)
          return obj unless obj.is_a?(String)

          Canon::YamlParsing.safe_load(obj, aliases: true)
        end
      end
    end
  end
end
