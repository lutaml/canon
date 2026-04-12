# frozen_string_literal: true

require_relative "base_resolver"

module Canon
  module Comparison
    module MatchOptions
      # XML/HTML-specific match options resolver
      class XmlResolver < BaseResolver
        # Format-specific defaults for XML/HTML
        #
        # Sensitive elements (preserve structural whitespace):
        # - XML: none by default — all structural whitespace stripped
        # - HTML: pre, code, textarea, script, style by default
        # Use preserve_whitespace_elements option to add elements that preserve whitespace.
        #
        FORMAT_DEFAULTS = {
          html: {
            preprocessing: :rendered,
            text_content: :normalize,
            structural_whitespace: :normalize,
            attribute_presence: :strict,
            attribute_order: :ignore,
            attribute_values: :strict,
            element_position: :ignore,
            comments: :ignore,
          },
          xml: {
            preprocessing: :none,
            text_content: :strict,
            structural_whitespace: :strict,
            attribute_presence: :strict,
            attribute_order: :ignore,
            attribute_values: :strict,
            element_position: :strict,
            comments: :strict,
          },
        }.freeze

        # Predefined match profiles for XML/HTML
        MATCH_PROFILES = {
          # Strict: Match exactly as written in source (XML default).
          # Structural whitespace is stripped by default for XML.
          # Use preserve_whitespace_elements to preserve structural whitespace in specific elements.
          strict: {
            preprocessing: :none,
            text_content: :strict,
            structural_whitespace: :strict,
            attribute_presence: :strict,
            attribute_order: :strict,
            attribute_values: :strict,
            element_position: :strict,
            comments: :strict,
          },

          # Rendered: Match rendered output (HTML default)
          # Mimics CSS whitespace collapsing
          rendered: {
            preprocessing: :none,
            text_content: :normalize,
            structural_whitespace: :normalize,
            attribute_presence: :strict,
            attribute_order: :strict,
            attribute_values: :strict,
            element_position: :strict,
            comments: :ignore,
          },

          # HTML4: Match HTML4 rendered output
          # HTML4 rendering normalizes attribute whitespace
          html4: {
            preprocessing: :rendered,
            text_content: :normalize,
            structural_whitespace: :normalize,
            attribute_presence: :strict,
            attribute_order: :strict,
            attribute_values: :normalize,
            element_position: :ignore,
            comments: :ignore,
          },

          # HTML5: Match HTML5 rendered output (same as rendered)
          html5: {
            preprocessing: :rendered,
            text_content: :normalize,
            structural_whitespace: :normalize,
            attribute_presence: :strict,
            attribute_order: :strict,
            attribute_values: :strict,
            element_position: :ignore,
            comments: :ignore,
          },

          # Spec-friendly: Formatting doesn't matter
          # Uses :rendered preprocessing for HTML which normalizes via to_html
          spec_friendly: {
            preprocessing: :rendered,
            text_content: :normalize,
            structural_whitespace: :ignore,
            attribute_presence: :strict,
            attribute_order: :ignore,
            attribute_values: :normalize,
            element_position: :ignore,
            comments: :ignore,
          },

          # Content-only: Only content matters
          content_only: {
            preprocessing: :c14n,
            text_content: :normalize,
            structural_whitespace: :ignore,
            attribute_presence: :strict,
            attribute_order: :ignore,
            attribute_values: :normalize,
            element_position: :ignore,
            comments: :ignore,
          },
        }.freeze

        class << self
          # Matching dimensions for XML/HTML (collectively exhaustive)
          def match_dimensions
            %i[
              text_content
              structural_whitespace
              attribute_presence
              attribute_order
              attribute_values
              element_position
              comments
            ].freeze
          end

          # Get format-specific default options
          #
          # @param format [Symbol] Format type (:xml or :html)
          # @return [Hash] Default options for the format
          def format_defaults(format)
            FORMAT_DEFAULTS[format]&.dup || FORMAT_DEFAULTS[:xml].dup
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

          # XML/HTML-specific dimension behaviors
          def dimension_behaviors
            {
              text_content: %i[strict normalize ignore].freeze,
              structural_whitespace: %i[strict normalize ignore].freeze,
              attribute_presence: %i[strict ignore].freeze,
              attribute_order: %i[strict ignore].freeze,
              attribute_values: %i[strict strip compact normalize
                                   ignore].freeze,
              element_position: %i[strict ignore].freeze,
              comments: %i[strict ignore].freeze,
            }
          end
        end
      end
    end
  end
end
