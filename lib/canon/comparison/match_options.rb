# frozen_string_literal: true

module Canon
  module Comparison
    # MECE Whitespace Matching Options for XML/HTML Comparison
    #
    # Provides a two-phase architecture for controlling comparison behavior:
    # 1. Preprocessing Phase: What to compare (none/c14n/normalize/format)
    # 2. Matching Phase: How to compare (4 dimensions × 3 behaviors)
    #
    # This design is based on HTML whitespace behavior as documented in:
    # https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_text/Whitespace
    module MatchOptions
      # Preprocessing options - what to do before comparison
      PREPROCESSING_OPTIONS = %i[none c14n normalize format].freeze

      # Whitespace matching behaviors (mutually exclusive)
      MATCH_BEHAVIORS = %i[strict normalize ignore].freeze

      # Whitespace matching dimensions (collectively exhaustive)
      MATCH_DIMENSIONS = %i[
        text_content
        structural_whitespace
        attribute_whitespace
        comments
      ].freeze

      # Format-specific defaults
      #
      # HTML defaults mimic CSS rendering behavior (whitespace collapsing)
      # XML defaults respect mixed content semantics (strict matching)
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
        json: {
          preprocessing: :none,
          text_content: :strict,
          structural_whitespace: :ignore,
          attribute_whitespace: :strict,
          comments: :ignore,
        },
        yaml: {
          preprocessing: :none,
          text_content: :strict,
          structural_whitespace: :ignore,
          attribute_whitespace: :strict,
          comments: :ignore,
        },
      }.freeze

      # Predefined match profiles
      MATCH_PROFILES = {
        # Strict: Match exactly as written in source (XML default behavior)
        strict: {
          preprocessing: :none,
          text_content: :strict,
          structural_whitespace: :strict,
          attribute_whitespace: :strict,
          comments: :strict,
        },

        # Rendered: Match rendered output (HTML default behavior)
        # Mimics CSS whitespace collapsing as per MDN spec
        rendered: {
          preprocessing: :none,
          text_content: :normalize,
          structural_whitespace: :normalize,
          attribute_whitespace: :strict,
          comments: :ignore,
        },

        # Spec-friendly: Formatting doesn't matter (test specifications)
        spec_friendly: {
          preprocessing: :normalize,
          text_content: :normalize,
          structural_whitespace: :ignore,
          attribute_whitespace: :strict,
          comments: :ignore,
        },

        # Content-only: Only content matters, structure doesn't
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
        # 1. Explicit match_options parameter
        # 2. Profile from match_profile parameter
        # 3. Global configuration
        # 4. Format-specific defaults
        #
        # @param format [Symbol] Format type (:xml, :html, :json, :yaml)
        # @param match_profile [Symbol, nil] Profile name
        # @param match_options [Hash, nil] Explicit options per dimension
        # @param preprocessing [Symbol, nil] Preprocessing option
        # @param global_profile [Symbol, nil] Global configured profile
        # @param global_options [Hash, nil] Global configured options
        # @return [Hash] Resolved options for all dimensions
        def resolve(
          format:,
          match_profile: nil,
          match_options: nil,
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
          if match_options
            validate_match_options!(match_options)
            options.merge!(match_options)
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

        # Convert match options to legacy options for backward compatibility
        #
        # @param match_options [Hash] Match options per dimension
        # @return [Hash] Legacy options
        # @deprecated Use match_profile and match_options instead
        def to_legacy_options(match_options)
          {
            collapse_whitespace:
              match_options[:structural_whitespace] == :ignore,
            normalize_tag_whitespace:
              match_options[:text_content] == :normalize,
            ignore_comments:
              match_options[:comments] != :strict,
          }
        end

        # Convert legacy options to match options
        #
        # @param opts [Hash] Legacy options
        # @return [Hash] Match options
        # @deprecated Legacy conversion for backward compatibility
        def from_legacy_options(opts)
          options = {}

          # Map legacy collapse_whitespace
          if opts.key?(:collapse_whitespace)
            options[:structural_whitespace] =
              opts[:collapse_whitespace] ? :ignore : :strict
          end

          # Map legacy normalize_tag_whitespace
          if opts.key?(:normalize_tag_whitespace)
            options[:text_content] =
              opts[:normalize_tag_whitespace] ? :normalize : :strict
          end

          # Map legacy ignore_comments
          if opts.key?(:ignore_comments)
            options[:comments] = opts[:ignore_comments] ? :ignore : :strict
          end

          options
        end

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
        # Mimics HTML whitespace collapsing per MDN spec
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
            .gsub(/[\p{Space}\u00a0]+/, " ") # Collapse all whitespace (ASCII + Unicode) to single space
            .strip # Remove leading/trailing whitespace
        end

        private

        # Validate preprocessing option
        def validate_preprocessing!(preprocessing)
          unless PREPROCESSING_OPTIONS.include?(preprocessing)
            raise Canon::Error,
                  "Unknown preprocessing option: #{preprocessing}. " \
                  "Valid options: #{PREPROCESSING_OPTIONS.join(', ')}"
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

            unless MATCH_BEHAVIORS.include?(behavior)
              raise Canon::Error,
                    "Unknown match behavior: #{behavior} for #{dimension}. " \
                    "Valid behaviors: #{MATCH_BEHAVIORS.join(', ')}"
            end
          end
        end
      end
    end
  end
end
