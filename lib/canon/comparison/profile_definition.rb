# frozen_string_literal: true

require_relative "match_options"

module Canon
  module Comparison
    # Profile definition DSL with full validation
    #
    # Provides a clean, validated way to define custom comparison profiles.
    # Catches errors at definition time with clear, actionable messages.
    #
    # @example Define a custom profile
    #   Canon::Comparison.define_profile(:my_custom) do
    #     text_content :normalize
    #     comments :ignore
    #     preprocessing :rendered
    #   end
    class ProfileDefinition
      # All valid dimensions for XML/HTML comparison
      # These must match MatchOptions::Xml::MATCH_DIMENSIONS
      VALID_DIMENSIONS = %i[
        text_content
        structural_whitespace
        attribute_presence
        attribute_order
        attribute_values
        element_position
        comments
      ].freeze

      # Behaviors valid for each dimension
      # Maps dimension name to array of valid behavior symbols
      DIMENSION_BEHAVIORS = {
        text_content: %i[strict normalize ignore],
        structural_whitespace: %i[strict normalize ignore],
        attribute_presence: %i[strict ignore],
        attribute_order: %i[strict ignore],
        attribute_values: %i[strict strip compact normalize ignore],
        element_position: %i[strict ignore],
        comments: %i[strict ignore],
      }.freeze

      attr_reader :name, :settings

      # Initialize a new profile definition
      #
      # @param name [Symbol] Profile name
      def initialize(name)
        @name = name
        @settings = {}
      end

      # Define a profile using DSL syntax
      #
      # @param name [Symbol] Profile name
      # @yield [ProfileDefinition] DSL block for defining profile
      # @return [Hash] Profile settings hash
      # @raise [ProfileError] if profile definition is invalid
      def self.define(name, &block)
        definition = new(name)
        definition.instance_eval(&block) if block
        definition.validate!
        definition.to_h
      end

      # Create DSL methods for each dimension
      VALID_DIMENSIONS.each do |dimension|
        define_method(dimension) do |behavior|
          @settings[dimension] = behavior
        end
      end

      # Set preprocessing mode
      #
      # @param mode [Symbol] Preprocessing mode
      # @raise [ProfileError] if mode is invalid
      def preprocessing(mode)
        unless MatchOptions::PREPROCESSING_OPTIONS.include?(mode)
          raise ProfileError,
                "Invalid preprocessing mode: #{mode}. " \
                "Valid options: #{MatchOptions::PREPROCESSING_OPTIONS.join(', ')}"
        end

        @settings[:preprocessing] = mode
      end

      # Enable/disable semantic diff
      #
      # @param enabled [Boolean] Whether to enable semantic diff (default: true)
      def semantic_diff(enabled: true)
        @settings[:semantic_diff] = enabled
      end

      # Set similarity threshold for semantic matching
      #
      # @param value [Numeric] Threshold between 0 and 1
      # @raise [ProfileError] if value is out of range
      def similarity_threshold(value)
        unless value.is_a?(Numeric) && value >= 0 && value <= 1
          raise ProfileError,
                "Similarity threshold must be between 0 and 1, got: #{value}"
        end

        @settings[:similarity_threshold] = value
      end

      # Validate the profile definition
      #
      # @raise [ProfileError] if profile definition is invalid
      def validate!
        @settings.each do |key, value|
          validate_dimension!(key, value) if VALID_DIMENSIONS.include?(key)
        end
      end

      # Convert to hash
      #
      # @return [Hash] Profile settings
      def to_h
        @settings.dup
      end

      private

      # Validate a dimension setting
      #
      # @param dimension [Symbol] Dimension name
      # @param behavior [Symbol] Behavior value
      # @raise [ProfileError] if dimension or behavior is invalid
      def validate_dimension!(dimension, behavior)
        unless DIMENSION_BEHAVIORS.key?(dimension)
          raise ProfileError,
                "Unknown dimension: #{dimension}. " \
                "Valid dimensions: #{VALID_DIMENSIONS.join(', ')}"
        end

        valid_behaviors = DIMENSION_BEHAVIORS[dimension]
        unless valid_behaviors.include?(behavior)
          raise ProfileError,
                "Invalid behavior '#{behavior}' for dimension '#{dimension}'. " \
                "Valid behaviors: #{valid_behaviors.join(', ')}"
        end
      end
    end

    # Custom error for profile definition issues
    class ProfileError < ::Canon::Error; end
  end
end
