# frozen_string_literal: true

module Canon
  module Diff
    # Represents a semantic difference between two nodes in a comparison tree
    # This is created during the Comparison Layer and carries information about
    # which dimension caused the difference and whether it's normative or informative
    class DiffNode
      attr_reader :node1, :node2
      attr_accessor :dimension, :reason, :normative, :formatting

      # @param node1 [Object] The first node being compared
      # @param node2 [Object] The second node being compared
      # @param dimension [Symbol] The match dimension that caused this diff
      #   (e.g., :text_content, :attribute_whitespace, :structural_whitespace,
      #   :comments, :key_order)
      # @param reason [String] Human-readable explanation of the difference
      def initialize(node1:, node2:, dimension:, reason:)
        @node1 = node1
        @node2 = node2
        @dimension = dimension
        @reason = reason
        @normative = nil # Will be set by DiffClassifier
        @formatting = nil # Will be set by DiffClassifier
      end

      # @return [Boolean] true if this diff is normative (affects equivalence)
      # Formatting-only diffs are never normative
      def normative?
        return false if formatting?

        @normative == true
      end

      # @return [Boolean] true if this diff is informative only (doesn't affect equivalence)
      # Formatting-only diffs are never informative
      def informative?
        return false if formatting?

        @normative == false
      end

      # @return [Boolean] true if this diff is formatting-only (purely cosmetic)
      # Formatting diffs are whitespace/line break differences with no semantic meaning
      def formatting?
        @formatting == true
      end

      def to_h
        {
          node1: node1,
          node2: node2,
          dimension: dimension,
          reason: reason,
          normative: normative,
          formatting: formatting,
        }
      end

      def ==(other)
        other.is_a?(DiffNode) &&
          node1 == other.node1 &&
          node2 == other.node2 &&
          dimension == other.dimension &&
          reason == other.reason &&
          normative == other.normative &&
          formatting == other.formatting
      end
    end
  end
end
