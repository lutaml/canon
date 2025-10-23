# frozen_string_literal: true

require_relative "../comparison/match_options"

module Canon
  module Options
    # Centralized registry for all Canon options
    # This is the SINGLE SOURCE OF TRUTH for option definitions
    # All interfaces (CLI, Ruby API, RSpec) auto-generate from this registry
    class Registry
      class << self
        # Get all option definitions
        def all_options
          @all_options ||= [
            preprocessing_option,
            diff_algorithm_option,
            diff_mode_option,
            *match_dimension_options,
            match_profile_option,
            *diff_formatting_options,
          ].freeze
        end

        # Get options applicable to a specific format
        def options_for_format(format)
          all_options.select do |opt|
            opt[:applies_to].nil? || opt[:applies_to].include?(format)
          end
        end

        # Validate options hash against registry
        def validate_options!(opts, format)
          valid_option_names = options_for_format(format).map { |o| o[:name] }
          invalid = opts.keys - valid_option_names
          return if invalid.empty?

          raise Canon::Error,
                "Invalid options for #{format}: #{invalid.join(', ')}"
        end

        # Get CLI flag name for an option
        def cli_flag_for(option_name)
          opt = all_options.find { |o| o[:name] == option_name }
          opt&.dig(:cli_flag)
        end

        # Get default value for an option
        def default_for(option_name, format = nil)
          opt = all_options.find { |o| o[:name] == option_name }
          return nil unless opt

          # Check for format-specific default
          if format && opt[:format_defaults]&.key?(format)
            opt[:format_defaults][format]
          else
            opt[:default]
          end
        end

        private

        # Preprocessing option
        def preprocessing_option
          {
            name: :preprocessing,
            type: :enum,
            values: %w[none c14n normalize format],
            default: :none,
            cli_flag: "--preprocessing",
            description: "Preprocessing: none, c14n, normalize, or format",
            applies_to: %i[xml html json yaml],
          }
        end

        # Diff algorithm option (NEW)
        def diff_algorithm_option
          {
            name: :diff_algorithm,
            type: :enum,
            values: %w[dom semantic],
            default: :dom,
            cli_flag: "--diff-algorithm",
            aliases: ["-a"],
            description: "Diff algorithm: dom (positional) or semantic (tree-based)",
            applies_to: %i[xml html json yaml],
          }
        end

        # Diff mode option (replaces --by-line flag)
        def diff_mode_option
          {
            name: :diff_mode,
            type: :enum,
            values: %w[by_line by_object],
            default: :by_object,
            format_defaults: {
              html: :by_line,
            },
            cli_flag: "--diff-mode",
            description: "Diff output mode: by_line or by_object",
            applies_to: %i[xml html json yaml],
          }
        end

        # Match profile option
        def match_profile_option
          {
            name: :match_profile,
            type: :enum,
            values: Canon::Comparison::MatchOptions::MATCH_PROFILES.keys.map(&:to_s),
            default: nil,
            cli_flag: "--match-profile",
            aliases: ["-p"],
            description: "Match profile: strict, rendered, spec_friendly, or content_only",
            applies_to: %i[xml html json yaml],
          }
        end

        # Match dimension options (generated from MatchOptions)
        def match_dimension_options
          Canon::Comparison::MatchOptions::MATCH_DIMENSIONS.map do |dim|
            {
              name: dim,
              type: :enum,
              values: behaviors_for_dimension(dim),
              default: nil,
              format_defaults: format_defaults_for_dimension(dim),
              cli_flag: "--#{dim.to_s.tr('_', '-')}",
              description: "#{dimension_description(dim)}: #{behaviors_for_dimension(dim).join(', ')}",
              applies_to: applicable_formats_for_dimension(dim),
            }
          end
        end

        # Diff formatting options
        def diff_formatting_options
          [
            {
              name: :color,
              type: :boolean,
              default: true,
              cli_flag: "--color",
              description: "Colorize diff output",
              applies_to: %i[xml html json yaml],
            },
            {
              name: :verbose,
              type: :boolean,
              default: false,
              cli_flag: "--verbose",
              aliases: ["-v"],
              description: "Show detailed differences",
              applies_to: %i[xml html json yaml],
            },
            {
              name: :context_lines,
              type: :numeric,
              default: 3,
              cli_flag: "--context-lines",
              description: "Number of context lines around changes",
              applies_to: %i[xml html json yaml],
            },
            {
              name: :diff_grouping_lines,
              type: :numeric,
              default: nil,
              cli_flag: "--diff-grouping-lines",
              description: "Group diffs within N lines into context blocks",
              applies_to: %i[xml html json yaml],
            },
          ]
        end

        # Get valid behaviors for a dimension
        def behaviors_for_dimension(dimension)
          case dimension
          when :key_order, :attribute_order,
               :element_structure, :element_position, :element_hierarchy
            %w[strict ignore]
          else
            %w[strict normalize ignore]
          end
        end

        # Get format defaults for a dimension from MatchOptions
        def format_defaults_for_dimension(dimension)
          Canon::Comparison::MatchOptions::FORMAT_DEFAULTS
            .transform_values { |v| v[dimension] }
            .compact
        end

        # Get applicable formats for a dimension
        def applicable_formats_for_dimension(dimension)
          case dimension
          when :attribute_whitespace, :attribute_order, :attribute_values
            %i[xml html]
          when :key_order
            %i[json yaml]
          else
            %i[xml html json yaml]
          end
        end

        # Get human-readable description for a dimension
        def dimension_description(dimension)
          case dimension
          when :text_content
            "Text content matching"
          when :structural_whitespace
            "Structural whitespace matching"
          when :attribute_whitespace
            "Attribute whitespace matching (XML/HTML only)"
          when :attribute_order
            "Attribute ordering (XML/HTML only)"
          when :attribute_values
            "Attribute value matching (XML/HTML only)"
          when :key_order
            "Key ordering (JSON/YAML only)"
          when :comments
            "Comment matching"
          when :element_structure
            "Element type/structure matching (semantic diff)"
          when :element_position
            "Element position/order matching (semantic diff)"
          when :element_hierarchy
            "Element hierarchy/parent-child matching (semantic diff)"
          else
            dimension.to_s.tr("_", " ").capitalize
          end
        end
      end
    end
  end
end
