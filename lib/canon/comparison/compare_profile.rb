# frozen_string_literal: true

module Canon
  module Comparison
    # CompareProfile encapsulates the policy decisions about how differences
    # in various dimensions should be handled during comparison
    #
    # This class provides separation of concerns:
    # - CompareProfile: Policy decisions (what to track, what affects equivalence)
    # - Comparator: Comparison logic (detect differences)
    # - DiffClassifier: Classification logic (normative vs informative vs formatting)
    class CompareProfile
      attr_reader :match_options

      # @param match_options [ResolvedMatchOptions, Hash] The match options to use
      def initialize(match_options)
        @match_options = match_options
      end

      # Should DiffNodes be created for differences in this dimension?
      #
      # In verbose mode, we want to track ALL differences for reporting.
      # In non-verbose mode, we only need to track normative differences.
      #
      # @param dimension [Symbol] The match dimension to check
      # @return [Boolean] true if differences should be tracked
      def track_dimension?(dimension)
        # Always track dimensions that affect equivalence
        # In verbose mode, also track informative dimensions
        true
      end

      # Should differences in this dimension affect equivalence?
      #
      # This determines the return value of the comparison:
      # - true: differences make documents non-equivalent
      # - false: differences are informative only
      #
      # @param dimension [Symbol] The match dimension to check
      # @return [Boolean] true if differences affect equivalence
      def affects_equivalence?(dimension)
        behavior = behavior_for(dimension)

        # :strict → affects equivalence
        # :normalize → might affect (if normalization fails)
        # :ignore → does NOT affect equivalence
        behavior != :ignore
      end

      # Is a difference in this dimension normative (affects equivalence)?
      #
      # This is used by DiffClassifier to determine the normative flag.
      #
      # @param dimension [Symbol] The match dimension to check
      # @return [Boolean] true if normative, false if informative
      def normative_dimension?(dimension)
        # Element structure changes are ALWAYS normative
        return true if dimension == :element_structure

        # If the dimension affects equivalence, it's normative
        affects_equivalence?(dimension)
      end

      # Can a difference in this dimension be formatting-only?
      #
      # This determines whether FormattingDetector should be applied.
      # Only text/content dimensions can have formatting-only differences.
      #
      # @param dimension [Symbol] The match dimension to check
      # @return [Boolean] true if formatting detection should apply
      def supports_formatting_detection?(dimension)
        # Only text/content dimensions can have formatting-only diffs
        text_dimensions = [:text_content, :structural_whitespace, :comments]
        text_dimensions.include?(dimension)
      end

      private

      # Get the behavior setting for a dimension
      # @param dimension [Symbol] The match dimension
      # @return [Symbol] The behavior (:strict, :normalize, :ignore)
      def behavior_for(dimension)
        # Handle both ResolvedMatchOptions and Hash
        if match_options.respond_to?(:behavior_for)
          match_options.behavior_for(dimension)
        elsif match_options.is_a?(Hash)
          match_options[dimension] || :strict
        else
          :strict
        end
      end
    end
  end
end