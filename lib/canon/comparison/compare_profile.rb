# frozen_string_literal: true

module Canon
  module Comparison
    # CompareProfile encapsulates the policy decisions about how differences
    # in various dimensions should be handled during comparison.
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

      def track_dimension?(_dimension)
        true
      end

      # Should differences in this dimension affect equivalence?
      #
      # @param dimension [Symbol] The match dimension to check
      # @return [Boolean] true if differences affect equivalence
      def affects_equivalence?(dimension)
        behavior = behavior_for(dimension)
        behavior != :ignore
      end

      # Is a difference in this dimension normative (affects equivalence)?
      #
      # Delegates to the Dimension object's normative? rule.  Falls back to
      # the default rule (normative unless :ignore) for dimensions not in the
      # format's dimension set (e.g., derived dimensions like :element_structure).
      #
      # @param dimension [Symbol] The match dimension to check
      # @return [Boolean] true if normative, false if informative
      def normative_dimension?(dimension)
        dim = dimension_for(dimension)
        if dim
          dim.normative?(behavior_for(dimension))
        else
          behavior_for(dimension) != :ignore
        end
      end

      # Can a difference in this dimension be formatting-only?
      #
      # Delegates to the Dimension object's supports_formatting_detection?
      # flag.  Falls back to false for unknown dimensions.
      #
      # @param dimension [Symbol] The match dimension to check
      # @return [Boolean] true if formatting detection should apply
      def supports_formatting_detection?(dimension)
        dim = dimension_for(dimension)
        dim ? dim.supports_formatting_detection? : false
      end

      # Get the behavior setting for a dimension
      # @param dimension [Symbol] The match dimension
      # @return [Symbol] The behavior (:strict, :normalize, :ignore)
      def behavior_for(dimension)
        if match_options.is_a?(ResolvedMatchOptions)
          match_options.behavior_for(dimension)
        elsif match_options.is_a?(Hash)
          match_options[dimension] || :strict
        else
          :strict
        end
      end

      private

      def dimension_for(name)
        set = Dimensions::Registry.for(extract_format)
        set[name]
      end

      def extract_format
        if match_options.is_a?(ResolvedMatchOptions)
          match_options.format
        elsif match_options.is_a?(Hash)
          match_options[:format]
        else
          :xml
        end
      end
    end
  end
end
