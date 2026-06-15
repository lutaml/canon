# frozen_string_literal: true

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
            whitespace_type: :strict,
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
            whitespace_type: :strict,
          },
        }.freeze

        # Predefined match profiles for XML/HTML
        MATCH_PROFILES = {
          strict: {
            preprocessing: :none,
            text_content: :strict,
            structural_whitespace: :strict,
            attribute_presence: :strict,
            attribute_order: :strict,
            attribute_values: :strict,
            element_position: :strict,
            comments: :strict,
            whitespace_type: :strict,
          },

          rendered: {
            preprocessing: :none,
            text_content: :normalize,
            structural_whitespace: :normalize,
            attribute_presence: :strict,
            attribute_order: :strict,
            attribute_values: :strict,
            element_position: :strict,
            comments: :ignore,
            whitespace_type: :strict,
          },

          html4: {
            preprocessing: :rendered,
            text_content: :normalize,
            structural_whitespace: :normalize,
            attribute_presence: :strict,
            attribute_order: :strict,
            attribute_values: :normalize,
            element_position: :ignore,
            comments: :ignore,
            whitespace_type: :strict,
          },

          html5: {
            preprocessing: :rendered,
            text_content: :normalize,
            structural_whitespace: :normalize,
            attribute_presence: :strict,
            attribute_order: :strict,
            attribute_values: :strict,
            element_position: :ignore,
            comments: :ignore,
            whitespace_type: :strict,
          },

          spec_friendly: {
            preprocessing: :rendered,
            text_content: :normalize,
            structural_whitespace: :ignore,
            attribute_presence: :strict,
            attribute_order: :ignore,
            attribute_values: :normalize,
            element_position: :ignore,
            comments: :ignore,
            whitespace_type: :strict,
          },

          content_only: {
            preprocessing: :c14n,
            text_content: :normalize,
            structural_whitespace: :ignore,
            attribute_presence: :strict,
            attribute_order: :ignore,
            attribute_values: :normalize,
            element_position: :ignore,
            comments: :ignore,
            whitespace_type: :strict,
          },
        }.freeze

        class << self
          # Get format-specific default options
          def format_defaults(format)
            FORMAT_DEFAULTS[format]&.dup || FORMAT_DEFAULTS[:xml].dup
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
            Canon::Comparison::Dimensions::Registry.for(:xml)
          end
        end
      end
    end
  end
end
