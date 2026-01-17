# frozen_string_literal: true

require_relative "base_resolver"

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
          # Strict: Match exactly
          strict: {
            preprocessing: :none,
            text_content: :strict,
            structural_whitespace: :strict,
            key_order: :strict,
          },

          # Spec-friendly: Formatting and order don't matter
          spec_friendly: {
            preprocessing: :normalize,
            text_content: :strict,
            structural_whitespace: :ignore,
            key_order: :ignore,
          },

          # Content-only: Only values matter
          content_only: {
            preprocessing: :normalize,
            text_content: :normalize,
            structural_whitespace: :ignore,
            key_order: :ignore,
          },
        }.freeze

        class << self
          # Matching dimensions for JSON (collectively exhaustive)
          def match_dimensions
            %i[
              text_content
              structural_whitespace
              key_order
            ].freeze
          end

          # Get format-specific default options
          #
          # @param format [Symbol] Format type (:json)
          # @return [Hash] Default options for the format
          def format_defaults(format)
            FORMAT_DEFAULTS[format]&.dup || FORMAT_DEFAULTS[:json].dup
          end

          # Get options for a named profile
          #
          # @param profile [Symbol] Profile name
          # @return [Hash] Profile options
          # @raise [Canon::Error] If profile is unknown
          def get_profile_options(profile)
            unless MATCH_PROFILES.key?(profile)
              raise Canon::Error,
                    "Unknown match profile: #{profile}. " \
                    "Valid profiles: #{MATCH_PROFILES.keys.join(', ')}"
            end
            MATCH_PROFILES[profile].dup
          end
        end
      end
    end
  end
end
