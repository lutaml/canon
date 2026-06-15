# frozen_string_literal: true

module Canon
  module Comparison
    module MatchOptions
      # YAML-specific match options resolver
      class YamlResolver < BaseResolver
        # Format defaults for YAML
        FORMAT_DEFAULTS = {
          yaml: {
            preprocessing: :none,
            text_content: :strict,
            structural_whitespace: :ignore,
            key_order: :ignore,
            comments: :ignore,
          },
        }.freeze

        # Predefined match profiles for YAML
        MATCH_PROFILES = {
          strict: {
            preprocessing: :none,
            text_content: :strict,
            structural_whitespace: :strict,
            key_order: :strict,
            comments: :strict,
          },

          spec_friendly: {
            preprocessing: :normalize,
            text_content: :strict,
            structural_whitespace: :ignore,
            key_order: :ignore,
            comments: :ignore,
          },

          content_only: {
            preprocessing: :normalize,
            text_content: :normalize,
            structural_whitespace: :ignore,
            key_order: :ignore,
            comments: :ignore,
          },
        }.freeze

        class << self
          # Get format-specific default options
          def format_defaults(format)
            FORMAT_DEFAULTS[format]&.dup || FORMAT_DEFAULTS[:yaml].dup
          end

          # Get options for a named profile
          def get_profile_options(profile)
            unless MATCH_PROFILES.key?(profile)
              raise Canon::Error,
                    "Unknown match profile: #{profile}. " \
                    "Valid profiles: #{MATCH_PROFILES.keys.join(', ')}"
            end
            MATCH_PROFILES[profile].dup
          end

          protected

          def dimension_set
            Canon::Comparison::Dimensions::Registry.for(:yaml)
          end
        end
      end
    end
  end
end
