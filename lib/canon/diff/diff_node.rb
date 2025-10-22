# frozen_string_literal: true

module Canon
  module Diff
    # Represents a semantic difference between two nodes in a comparison tree
    # This is created during the Comparison Layer and carries information about
    # which dimension caused the difference and whether it's normative or informative
    class DiffNode
      attr_reader :node1, :node2, :dimension, :reason
      attr_accessor :normative

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
      end

      # @return [Boolean] true if this diff is normative (affects equivalence)
      def normative?
        @normative == true
      end

      # @return [Boolean] true if this diff is informative only (doesn't affect equivalence)
      def informative?
        @normative == false
      end

      def to_h
        {
          node1: node1,
          node2: node2,
          dimension: dimension,
          reason: reason,
          normative: normative,
        }
      end

      def ==(other)
        other.is_a?(DiffNode) &&
          node1 == other.node1 &&
          node2 == other.node2 &&
          dimension == other.dimension &&
          reason == other.reason &&
          normative == other.normative
      end
    end
  end
end
