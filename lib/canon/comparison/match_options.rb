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
    module MatchOptions
      # Preprocessing options - what to do before comparison
      PREPROCESSING_OPTIONS = %i[none c14n normalize format rendered].freeze

      # Matching behaviors (mutually exclusive)
      MATCH_BEHAVIORS = %i[strict normalize ignore].freeze

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
      end

      # XML/HTML-specific matching options
      module Xml
        # Matching dimensions for XML/HTML (collectively exhaustive)
        MATCH_DIMENSIONS = %i[
          text_content
          structural_whitespace
          attribute_whitespace
          comments
        ].freeze

        # Format-specific defaults
        FORMAT_DEFAULTS = {
          html: {
            preprocessing: :none,
            text_content: :normalize,
            structural_whitespace: :normalize,
            attribute_whitespace: :strict,
            comments: :ignore,
          },
          xml: {
            preprocessing: :none,
            text_content: :strict,
            structural_whitespace: :strict,
            attribute_whitespace: :strict,
            comments: :strict,
          },
        }.freeze

        # Predefined match profiles for XML/HTML
        MATCH_PROFILES = {
          # Strict: Match exactly as written in source (XML default)
          strict: {
            preprocessing: :none,
            text_content: :strict,
            structural_whitespace: :strict,
            attribute_whitespace: :strict,
            comments: :strict,
          },

          # Rendered: Match rendered output (HTML default)
          # Mimics CSS whitespace collapsing
          rendered: {
            preprocessing: :none,
            text_content: :normalize,
            structural_whitespace: :normalize,
            attribute_whitespace: :strict,
            comments: :ignore,
          },

          # Spec-friendly: Formatting doesn't matter
          # Uses :rendered preprocessing for HTML which normalizes via to_html
          spec_friendly: {
            preprocessing: :rendered,
            text_content: :normalize,
            structural_whitespace: :ignore,
            attribute_whitespace: :strict,
            comments: :ignore,
          },

          # Content-only: Only content matters
          content_only: {
            preprocessing: :c14n,
            text_content: :normalize,
            structural_whitespace: :ignore,
            attribute_whitespace: :normalize,
            comments: :ignore,
          },
        }.freeze

        class << self
          # Resolve match options with precedence handling
          #
          # Precedence order (highest to lowest):
          # 1. Explicit match parameter
          # 2. Profile from match_profile parameter
          # 3. Global configuration
          # 4. Format-specific defaults
          #
          # @param format [Symbol] Format type (:xml or :html)
          # @param match_profile [Symbol, nil] Profile name
          # @param match [Hash, nil] Explicit options per dimension
          # @param preprocessing [Symbol, nil] Preprocessing option
          # @param global_profile [Symbol, nil] Global configured profile
          # @param global_options [Hash, nil] Global configured options
          # @return [Hash] Resolved options for all dimensions
          def resolve(
            format:,
            match_profile: nil,
            match: nil,
            preprocessing: nil,
            global_profile: nil,
            global_options: nil
          )
            # Start with format-specific defaults
            options = FORMAT_DEFAULTS[format]&.dup || FORMAT_DEFAULTS[:xml].dup

            # Apply global profile if specified
            if global_profile
              profile_opts = get_profile_options(global_profile)
              options.merge!(profile_opts)
            end

            # Apply global options if specified
            if global_options
              validate_match_options!(global_options)
              options.merge!(global_options)
            end

            # Apply per-call profile if specified (overrides global)
            if match_profile
              profile_opts = get_profile_options(match_profile)
              options.merge!(profile_opts)
            end

            # Apply per-call preprocessing if specified (overrides profile)
            if preprocessing
              validate_preprocessing!(preprocessing)
              options[:preprocessing] = preprocessing
            end

            # Apply per-call explicit options if specified (highest priority)
            if match
              validate_match_options!(match)
              options.merge!(match)
            end

            options
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

          private

          # Validate preprocessing option
          def validate_preprocessing!(preprocessing)
            unless MatchOptions::PREPROCESSING_OPTIONS.include?(preprocessing)
              raise Canon::Error,
                    "Unknown preprocessing option: #{preprocessing}. " \
                    "Valid options: #{MatchOptions::PREPROCESSING_OPTIONS.join(', ')}"
            end
          end

          # Validate match options
          def validate_match_options!(match_options)
            match_options.each do |dimension, behavior|
              # Skip preprocessing as it's validated separately
              next if dimension == :preprocessing

              unless MATCH_DIMENSIONS.include?(dimension)
                raise Canon::Error,
                      "Unknown match dimension: #{dimension}. " \
                      "Valid dimensions: #{MATCH_DIMENSIONS.join(', ')}"
              end

              unless MatchOptions::MATCH_BEHAVIORS.include?(behavior)
                raise Canon::Error,
                      "Unknown match behavior: #{behavior} for #{dimension}. " \
                      "Valid behaviors: #{MatchOptions::MATCH_BEHAVIORS.join(', ')}"
              end
            end
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

        # Format defaults for JSON
        FORMAT_DEFAULTS = {
          json: {
            preprocessing: :none,
            text_content: :strict,
            structural_whitespace: :ignore,
            key_order: :strict,
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
          # Resolve match options with precedence handling
          #
          # @param format [Symbol] Format type (:json)
          # @param match_profile [Symbol, nil] Profile name
          # @param match [Hash, nil] Explicit options per dimension
          # @param preprocessing [Symbol, nil] Preprocessing option
          # @param global_profile [Symbol, nil] Global configured profile
          # @param global_options [Hash, nil] Global configured options
          # @return [Hash] Resolved options for all dimensions
          def resolve(
            format:,
            match_profile: nil,
            match: nil,
            preprocessing: nil,
            global_profile: nil,
            global_options: nil
          )
            # Start with format-specific defaults
            options = FORMAT_DEFAULTS[:json].dup

            # Apply global profile if specified
            if global_profile
              profile_opts = get_profile_options(global_profile)
              options.merge!(profile_opts)
            end

            # Apply global options if specified
            if global_options
              validate_match_options!(global_options)
              options.merge!(global_options)
            end

            # Apply per-call profile if specified (overrides global)
            if match_profile
              profile_opts = get_profile_options(match_profile)
              options.merge!(profile_opts)
            end

            # Apply per-call preprocessing if specified (overrides profile)
            if preprocessing
              validate_preprocessing!(preprocessing)
              options[:preprocessing] = preprocessing
            end

            # Apply per-call explicit options if specified (highest priority)
            if match
              validate_match_options!(match)
              options.merge!(match)
            end

            options
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

          private

          # Validate preprocessing option
          def validate_preprocessing!(preprocessing)
            unless MatchOptions::PREPROCESSING_OPTIONS.include?(preprocessing)
              raise Canon::Error,
                    "Unknown preprocessing option: #{preprocessing}. " \
                    "Valid options: #{MatchOptions::PREPROCESSING_OPTIONS.join(', ')}"
            end
          end

          # Validate match options
          def validate_match_options!(match_options)
            match_options.each do |dimension, behavior|
              # Skip preprocessing as it's validated separately
              next if dimension == :preprocessing

              unless MATCH_DIMENSIONS.include?(dimension)
                raise Canon::Error,
                      "Unknown match dimension: #{dimension}. " \
                      "Valid dimensions: #{MATCH_DIMENSIONS.join(', ')}"
              end

              unless MatchOptions::MATCH_BEHAVIORS.include?(behavior)
                raise Canon::Error,
                      "Unknown match behavior: #{behavior} for #{dimension}. " \
                      "Valid behaviors: #{MatchOptions::MATCH_BEHAVIORS.join(', ')}"
              end
            end
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

        # Format defaults for YAML
        FORMAT_DEFAULTS = {
          yaml: {
            preprocessing: :none,
            text_content: :strict,
            structural_whitespace: :ignore,
            key_order: :strict,
            comments: :ignore,
          },
        }.freeze

        # Predefined match profiles for YAML
        MATCH_PROFILES = {
          # Strict: Match exactly
          strict: {
            preprocessing: :none,
            text_content: :strict,
            structural_whitespace: :strict,
            key_order: :strict,
            comments: :strict,
          },

          # Spec-friendly: Formatting and order don't matter
          spec_friendly: {
            preprocessing: :normalize,
            text_content: :strict,
            structural_whitespace: :ignore,
            key_order: :ignore,
            comments: :ignore,
          },

          # Content-only: Only values matter
          content_only: {
            preprocessing: :normalize,
            text_content: :normalize,
            structural_whitespace: :ignore,
            key_order: :ignore,
            comments: :ignore,
          },
        }.freeze

        class << self
          # Resolve match options with precedence handling
          #
          # @param format [Symbol] Format type (:yaml)
          # @param match_profile [Symbol, nil] Profile name
          # @param match [Hash, nil] Explicit options per dimension
          # @param preprocessing [Symbol, nil] Preprocessing option
          # @param global_profile [Symbol, nil] Global configured profile
          # @param global_options [Hash, nil] Global configured options
          # @return [Hash] Resolved options for all dimensions
          def resolve(
            format:,
            match_profile: nil,
            match: nil,
            preprocessing: nil,
            global_profile: nil,
            global_options: nil
          )
            # Start with format-specific defaults
            options = FORMAT_DEFAULTS[:yaml].dup

            # Apply global profile if specified
            if global_profile
              profile_opts = get_profile_options(global_profile)
              options.merge!(profile_opts)
            end

            # Apply global options if specified
            if global_options
              validate_match_options!(global_options)
              options.merge!(global_options)
            end

            # Apply per-call profile if specified (overrides global)
            if match_profile
              profile_opts = get_profile_options(match_profile)
              options.merge!(profile_opts)
            end

            # Apply per-call preprocessing if specified (overrides profile)
            if preprocessing
              validate_preprocessing!(preprocessing)
              options[:preprocessing] = preprocessing
            end

            # Apply per-call explicit options if specified (highest priority)
            if match
              validate_match_options!(match)
              options.merge!(match)
            end

            options
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

          private

          # Validate preprocessing option
          def validate_preprocessing!(preprocessing)
            unless MatchOptions::PREPROCESSING_OPTIONS.include?(preprocessing)
              raise Canon::Error,
                    "Unknown preprocessing option: #{preprocessing}. " \
                    "Valid options: #{MatchOptions::PREPROCESSING_OPTIONS.join(', ')}"
            end
          end

          # Validate match options
          def validate_match_options!(match_options)
            match_options.each do |dimension, behavior|
              # Skip preprocessing as it's validated separately
              next if dimension == :preprocessing

              unless MATCH_DIMENSIONS.include?(dimension)
                raise Canon::Error,
                      "Unknown match dimension: #{dimension}. " \
                      "Valid dimensions: #{MATCH_DIMENSIONS.join(', ')}"
              end

              unless MatchOptions::MATCH_BEHAVIORS.include?(behavior)
                raise Canon::Error,
                      "Unknown match behavior: #{behavior} for #{dimension}. " \
                      "Valid behaviors: #{MatchOptions::MATCH_BEHAVIORS.join(', ')}"
              end
            end
          end
        end
      end
    end
  end
end
