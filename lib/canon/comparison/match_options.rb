# frozen_string_literal: true

require_relative "match_options/base_resolver"
require_relative "match_options/xml_resolver"
require_relative "match_options/json_resolver"
require_relative "match_options/yaml_resolver"

module Canon
  module Comparison
    # Matching Options for Canon Comparison
    #
    # Provides a two-phase architecture for controlling comparison behavior:
    # 1. Preprocessing Phase: What to compare (none/c14n/normalize/format)
    # 2. Matching Phase: How to compare (dimensions × behaviors)
    #
    # Format-specific modules define appropriate dimensions for each format:
    # - Xml/Html: text_content, structural_whitespace, attribute_whitespace, comments
    # - Json/Yaml: text_content, structural_whitespace, key_order, comments

    # Wrapper class for resolved match options
    # Provides convenient methods for accessing behaviors by dimension
    class ResolvedMatchOptions
      attr_reader :options, :format, :compare_profile

      def initialize(options, format:, compare_profile: nil)
        @options = options
        @format = format
        @compare_profile = compare_profile
      end

      # Get the behavior for a specific dimension
      # @param dimension [Symbol] The match dimension
      # @return [Symbol] The behavior (:strict, :normalize, :ignore)
      def behavior_for(dimension)
        @options[dimension]
      end

      # Get the preprocessing option
      # @return [Symbol] The preprocessing option
      def preprocessing
        @options[:preprocessing]
      end

      # Check if semantic diff is enabled
      # @return [Boolean] true if semantic diff is enabled
      def semantic_diff?
        @options[:semantic_diff] == true
      end

      def to_h
        @options.dup
      end
    end

    # Module containing match option utilities and format-specific modules
    module MatchOptions
      # Preprocessing options - what to do before comparison
      PREPROCESSING_OPTIONS = %i[none c14n normalize format rendered].freeze

      # Matching behaviors (mutually exclusive)
      MATCH_BEHAVIORS = %i[strict strip compact normalize ignore].freeze

      class << self
        # Apply match behavior to text comparison
        #
        # @param text1 [String] First text
        # @param text2 [String] Second text
        # @param behavior [Symbol] Match behavior (:strict, :normalize, :ignore)
        # @return [Boolean] true if texts match according to behavior
        def match_text?(text1, text2, behavior)
          case behavior
          when :strict
            text1 == text2
          when :normalize
            normalize_text(text1) == normalize_text(text2)
          when :ignore
            true
          else
            raise Canon::Error, "Unknown match behavior: #{behavior}"
          end
        end

        # Normalize text by collapsing whitespace and trimming
        # Mimics HTML whitespace collapsing
        #
        # Handles both ASCII and Unicode whitespace characters including:
        # - Regular space (U+0020)
        # - Non-breaking space (U+00A0)
        # - Other Unicode whitespace per \p{Space}
        #
        # @param text [String] Text to normalize
        # @return [String] Normalized text
        def normalize_text(text)
          return "" if text.nil?

          text.to_s
            .gsub(/[\p{Space}\u00a0]+/, " ") # Collapse all whitespace to single space
            .strip # Remove leading/trailing whitespace
        end

        # Process attribute value according to match behavior
        #
        # @param value [String] Attribute value to process
        # @param behavior [Symbol] Match behavior (:strict, :strip, :compact, :normalize, :ignore)
        # @return [String] Processed value
        def process_attribute_value(value, behavior)
          case behavior
          when :strict
            value.to_s
          when :strip
            value.to_s.strip
          when :compact
            value.to_s.gsub(/[\p{Space}\u00a0]+/, " ")
          when :normalize
            normalize_text(value)
          when :ignore
            ""
          else
            raise Canon::Error, "Unknown attribute value behavior: #{behavior}"
          end
        end
      end

      # XML/HTML-specific matching options
      module Xml
        # Matching dimensions for XML/HTML (collectively exhaustive)
        MATCH_DIMENSIONS = %i[
          text_content
          structural_whitespace
          attribute_presence
          attribute_order
          attribute_values
          element_position
          comments
        ].freeze

        # Expose FORMAT_DEFAULTS from XmlResolver (for backward compatibility)
        FORMAT_DEFAULTS = MatchOptions::XmlResolver.const_get(:FORMAT_DEFAULTS)

        # Expose MATCH_PROFILES from XmlResolver (for backward compatibility)
        MATCH_PROFILES = MatchOptions::XmlResolver.const_get(:MATCH_PROFILES)

        class << self
          # Delegate to XmlResolver
          def resolve(**kwargs)
            MatchOptions::XmlResolver.resolve(**kwargs)
          end

          # Delegate to XmlResolver
          def get_profile_options(profile)
            MatchOptions::XmlResolver.get_profile_options(profile)
          end

          # Get valid match dimensions for XML/HTML
          #
          # @return [Array<Symbol>] Valid dimensions
          def match_dimensions
            MatchOptions::XmlResolver.match_dimensions
          end

          # Get format-specific default options
          #
          # @param format [Symbol] Format type
          # @return [Hash] Default options for the format
          def format_defaults(format)
            MatchOptions::XmlResolver.format_defaults(format)
          end
        end
      end

      # JSON-specific matching options
      module Json
        # Matching dimensions for JSON (collectively exhaustive)
        MATCH_DIMENSIONS = %i[
          text_content
          structural_whitespace
          key_order
        ].freeze

        # Expose FORMAT_DEFAULTS from JsonResolver (for backward compatibility)
        FORMAT_DEFAULTS = MatchOptions::JsonResolver.const_get(:FORMAT_DEFAULTS)

        # Expose MATCH_PROFILES from JsonResolver (for backward compatibility)
        MATCH_PROFILES = MatchOptions::JsonResolver.const_get(:MATCH_PROFILES)

        class << self
          # Delegate to JsonResolver
          def resolve(**kwargs)
            MatchOptions::JsonResolver.resolve(**kwargs)
          end

          # Delegate to JsonResolver
          def get_profile_options(profile)
            MatchOptions::JsonResolver.get_profile_options(profile)
          end

          # Get valid match dimensions for JSON
          #
          # @return [Array<Symbol>] Valid dimensions
          def match_dimensions
            MatchOptions::JsonResolver.match_dimensions
          end

          # Get format-specific default options
          #
          # @param format [Symbol] Format type
          # @return [Hash] Default options for the format
          def format_defaults(format)
            MatchOptions::JsonResolver.format_defaults(format)
          end
        end
      end

      # YAML-specific matching options
      module Yaml
        # Matching dimensions for YAML (collectively exhaustive)
        MATCH_DIMENSIONS = %i[
          text_content
          structural_whitespace
          key_order
          comments
        ].freeze

        # Expose FORMAT_DEFAULTS from YamlResolver (for backward compatibility)
        FORMAT_DEFAULTS = MatchOptions::YamlResolver.const_get(:FORMAT_DEFAULTS)

        # Expose MATCH_PROFILES from YamlResolver (for backward compatibility)
        MATCH_PROFILES = MatchOptions::YamlResolver.const_get(:MATCH_PROFILES)

        class << self
          # Delegate to YamlResolver
          def resolve(**kwargs)
            MatchOptions::YamlResolver.resolve(**kwargs)
          end

          # Delegate to YamlResolver
          def get_profile_options(profile)
            MatchOptions::YamlResolver.get_profile_options(profile)
          end

          # Get valid match dimensions for YAML
          #
          # @return [Array<Symbol>] Valid dimensions
          def match_dimensions
            MatchOptions::YamlResolver.match_dimensions
          end

          # Get format-specific default options
          #
          # @param format [Symbol] Format type
          # @return [Hash] Default options for the format
          def format_defaults(format)
            MatchOptions::YamlResolver.format_defaults(format)
          end
        end
      end
    end
  end
end
