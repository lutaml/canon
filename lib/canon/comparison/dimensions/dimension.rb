# frozen_string_literal: true

module Canon
  module Comparison
    module Dimensions
      # Immutable value object representing a single comparison dimension.
      #
      # A dimension is an aspect of a document that can be compared with
      # different behaviors (e.g., :strict, :normalize, :ignore).  Each
      # dimension knows its own classification rules — whether a difference
      # is normative (affects equivalence) for a given behavior, and whether
      # formatting detection should apply.
      class Dimension
        attr_reader :name, :valid_behaviors

        # @param name [Symbol] Dimension identifier (e.g., :text_content)
        # @param valid_behaviors [Array<Symbol>] Allowed behaviors
        # @param normative_rule [Symbol] :behavior_not_ignore or :strict_only
        # @param formatting_detection [Boolean] Whether FormattingDetector applies
        def initialize(name:, valid_behaviors:, normative_rule: :behavior_not_ignore,
                       formatting_detection: false)
          @name = name
          @valid_behaviors = valid_behaviors.freeze
          @normative_rule = normative_rule
          @formatting_detection = formatting_detection
          freeze
        end

        # Whether a difference in this dimension with the given behavior is
        # normative (affects equivalence).
        def normative?(behavior)
          case @normative_rule
          when :strict_only then behavior == :strict
          else behavior != :ignore
          end
        end

        # Whether the given behavior is valid for this dimension.
        def valid_behavior?(behavior)
          @valid_behaviors.include?(behavior)
        end

        # Whether formatting detection should apply to differences in this
        # dimension.
        def supports_formatting_detection?
          @formatting_detection
        end
      end
    end
  end
end
