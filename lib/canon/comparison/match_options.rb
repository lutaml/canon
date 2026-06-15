# frozen_string_literal: true

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

      def to_h
        @options.dup
      end
    end

    # Module containing match option utilities and format-specific modules
    module MatchOptions
      autoload :BaseResolver, "canon/comparison/match_options/base_resolver"
      autoload :JsonResolver, "canon/comparison/match_options/json_resolver"
      autoload :XmlResolver, "canon/comparison/match_options/xml_resolver"
      autoload :YamlResolver, "canon/comparison/match_options/yaml_resolver"

      # Preprocessing options - what to do before comparison
      PREPROCESSING_OPTIONS = %i[none c14n normalize format rendered].freeze

      # Matching behaviors (deprecated - use per-dimension validation instead)
      # This universal constant is kept for backward compatibility but should not
      # be used for validation. Use BaseResolver.dimension_behaviors instead.
      # Note: :strip and :compact are only valid for attribute_values dimension.
      MATCH_BEHAVIORS = %i[strict strip compact normalize ignore].freeze

      class << self
        # Apply match behavior to text comparison
        #
        # @param text1 [String] First text
        # @param text2 [String] Second text
        # @param behavior [Symbol] Match behavior (:strict, :normalize, :ignore)
        # @param whitespace_type [Symbol] Whitespace type handling (:strict, :normalize)
        # @return [Boolean] true if texts match according to behavior
        def match_text?(text1, text2, behavior, whitespace_type: :strict)
          case behavior
          when :strict
            text1 == text2
          when :normalize
            if whitespace_type == :normalize
              normalize_text(text1) == normalize_text(text2)
            else
              normalize_text_preserving_type(text1) == normalize_text_preserving_type(text2)
            end
          when :ignore
            true
          else
            raise Canon::Error, "Unknown match behavior: #{behavior}"
          end
        end

        # Normalize text by collapsing whitespace and trimming
        # Mimics HTML whitespace collapsing
        def normalize_text(text)
          return "" if text.nil?

          text.to_s
            .gsub(/[\p{Space} ]+/, " ") # Collapse all whitespace to single space
            .strip # Remove leading/trailing whitespace
        end

        # Normalize text preserving Unicode whitespace type distinctions.
        def normalize_text_preserving_type(text)
          return "" if text.nil?

          text.to_s
            .gsub(/[ \t\r\n\f\v]+/, " ") # Collapse only ASCII whitespace
            .strip
        end

        # Process attribute value according to match behavior
        def process_attribute_value(value, behavior)
          case behavior
          when :strict
            value.to_s
          when :strip
            value.to_s.strip
          when :compact
            value.to_s.gsub(/[\p{Space} ]+/, " ")
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
        # Single source of truth: derived from the DimensionSet in Registry.
        MATCH_DIMENSIONS = Dimensions::Registry.for(:xml).names.freeze

        # Expose FORMAT_DEFAULTS from XmlResolver (for backward compatibility)
        FORMAT_DEFAULTS = MatchOptions::XmlResolver.const_get(:FORMAT_DEFAULTS)

        # Expose MATCH_PROFILES from XmlResolver (for backward compatibility)
        MATCH_PROFILES = MatchOptions::XmlResolver.const_get(:MATCH_PROFILES)

        class << self
          def resolve(**kwargs)
            MatchOptions::XmlResolver.resolve(**kwargs)
          end

          def get_profile_options(profile)
            MatchOptions::XmlResolver.get_profile_options(profile)
          end

          def match_dimensions
            MatchOptions::XmlResolver.match_dimensions
          end

          def format_defaults(format)
            MatchOptions::XmlResolver.format_defaults(format)
          end
        end
      end

      # JSON-specific matching options
      module Json
        MATCH_DIMENSIONS = Dimensions::Registry.for(:json).names.freeze

        FORMAT_DEFAULTS = MatchOptions::JsonResolver.const_get(:FORMAT_DEFAULTS)

        MATCH_PROFILES = MatchOptions::JsonResolver.const_get(:MATCH_PROFILES)

        class << self
          def resolve(**kwargs)
            MatchOptions::JsonResolver.resolve(**kwargs)
          end

          def get_profile_options(profile)
            MatchOptions::JsonResolver.get_profile_options(profile)
          end

          def match_dimensions
            MatchOptions::JsonResolver.match_dimensions
          end

          def format_defaults(format)
            MatchOptions::JsonResolver.format_defaults(format)
          end
        end
      end

      # YAML-specific matching options
      module Yaml
        MATCH_DIMENSIONS = Dimensions::Registry.for(:yaml).names.freeze

        FORMAT_DEFAULTS = MatchOptions::YamlResolver.const_get(:FORMAT_DEFAULTS)

        MATCH_PROFILES = MatchOptions::YamlResolver.const_get(:MATCH_PROFILES)

        class << self
          def resolve(**kwargs)
            MatchOptions::YamlResolver.resolve(**kwargs)
          end

          def get_profile_options(profile)
            MatchOptions::YamlResolver.get_profile_options(profile)
          end

          def match_dimensions
            MatchOptions::YamlResolver.match_dimensions
          end

          def format_defaults(format)
            MatchOptions::YamlResolver.format_defaults(format)
          end
        end
      end
    end
  end
end
