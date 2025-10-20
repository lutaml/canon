# frozen_string_literal: true

module Canon
  module Diff
    # Represents a semantic difference between two nodes in a comparison tree
    # This is created during the Comparison Layer and carries information about
    # which dimension caused the difference and whether it's active or inactive
    class DiffNode
      attr_reader :node1, :node2, :dimension, :reason
      attr_accessor :active

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
        @active = nil # Will be set by DiffClassifier
      end

      # @return [Boolean] true if this diff is semantically meaningful
      def active?
        @active == true
      end

      # @return [Boolean] true if this diff is textual-only
      def inactive?
        @active == false
      end

      def to_h
        {
          node1: node1,
          node2: node2,
          dimension: dimension,
          reason: reason,
          active: active,
        }
      end

      def ==(other)
        other.is_a?(DiffNode) &&
          node1 == other.node1 &&
          node2 == other.node2 &&
          dimension == other.dimension &&
          reason == other.reason &&
          active == other.active
      end
    end
  end
end
