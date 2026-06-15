# frozen_string_literal: true

module Canon
  module Comparison
    module MatchOptions
      # JSON-specific match options resolver
      class JsonResolver < BaseResolver
        # Format defaults for JSON
        FORMAT_DEFAULTS = {
          json: {
            preprocessing: :none,
            text_content: :strict,
            structural_whitespace: :ignore,
            key_order: :ignore,
          },
        }.freeze

        # Predefined match profiles for JSON
        MATCH_PROFILES = {
          strict: {
            preprocessing: :none,
            text_content: :strict,
            structural_whitespace: :strict,
            key_order: :strict,
          },

          spec_friendly: {
            preprocessing: :normalize,
            text_content: :strict,
            structural_whitespace: :ignore,
            key_order: :ignore,
          },

          content_only: {
            preprocessing: :normalize,
            text_content: :normalize,
            structural_whitespace: :ignore,
            key_order: :ignore,
          },
        }.freeze

        class << self
          # Get format-specific default options
          def format_defaults(format)
            FORMAT_DEFAULTS[format]&.dup || FORMAT_DEFAULTS[:json].dup
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
            Canon::Comparison::Dimensions::Registry.for(:json)
          end
        end
      end
    end
  end
end
