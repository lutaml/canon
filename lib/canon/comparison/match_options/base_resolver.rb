# frozen_string_literal: true

module Canon
  module Comparison
    module MatchOptions
      # Base class for match option resolvers
      # Provides common resolve logic with format-specific customization
      class BaseResolver
        class << self
          # Resolve match options with precedence handling
          #
          # Precedence order (highest to lowest):
          # 1. Explicit match parameter
          # 2. Profile from match_profile parameter
          # 3. Global configuration
          # 4. Format-specific defaults
          #
          # @param format [Symbol] Format type
          # @param match_profile [Symbol, nil] Profile name
          # @param match [Hash, nil] Explicit options per dimension
          # @param preprocessing [Symbol, nil] Preprocessing option
          # @param global_profile [Symbol, nil] Global configured profile
          # @param global_options [Hash, nil] Global configured options
          # @return [Hash] Resolved options for all dimensions
          def resolve(format:, match_profile: nil, match: nil, preprocessing: nil,
                      global_profile: nil, global_options: nil)
            # Start with format-specific defaults
            options = format_defaults(format).dup

            # Store format for later use (e.g., WhitespaceSensitivity needs it)
            options[:format] = format

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

          # Get format-specific default options
          # Subclasses should override this
          #
          # @param format [Symbol] Format type
          # @return [Hash] Default options for the format
          def format_defaults(format)
            raise NotImplementedError,
                  "#{self.class} must implement #format_defaults"
          end

          # Get options for a named profile
          # Subclasses should override this
          #
          # @param profile [Symbol] Profile name
          # @return [Hash] Profile options
          # @raise [Canon::Error] If profile is unknown
          def get_profile_options(profile)
            raise NotImplementedError,
                  "#{self.class} must implement #get_profile_options"
          end

          # Get valid match dimensions for this format
          # Subclasses should override this
          #
          # @return [Array<Symbol>] Valid dimensions
          def match_dimensions
            raise NotImplementedError,
                  "#{self.class} must implement #match_dimensions"
          end

          protected

          # Validate preprocessing option
          #
          # @param preprocessing [Symbol] Preprocessing option
          # @raise [Canon::Error] If invalid
          def validate_preprocessing!(preprocessing)
            unless MatchOptions::PREPROCESSING_OPTIONS.include?(preprocessing)
              raise Canon::Error,
                    "Unknown preprocessing option: #{preprocessing}. " \
                    "Valid options: #{MatchOptions::PREPROCESSING_OPTIONS.join(', ')}"
            end
          end

          # Validate match options
          #
          # @param match_options [Hash] Options to validate
          # @raise [Canon::Error] If invalid dimension or behavior
          def validate_match_options!(match_options)
            # Special options that don't need validation as dimensions
            special_options = %i[
              format
              preprocessing
              semantic_diff
              similarity_threshold
              hash_matching
              similarity_matching
              propagation
              whitespace_sensitive_elements
              whitespace_insensitive_elements
              respect_xml_space
            ]

            match_options.each do |dimension, behavior|
              # Skip special options (validated elsewhere or passed through)
              next if special_options.include?(dimension)

              unless match_dimensions.include?(dimension)
                raise Canon::Error,
                      "Unknown match dimension: #{dimension}. " \
                      "Valid dimensions: #{match_dimensions.join(', ')}"
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
